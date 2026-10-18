"""Long-running backend for the Spark (no-cost) Firebase plan.

Does what the Cloud Functions would do on Blaze:
  * polls ThingSpeak and writes devices/{node}, readings and hourly rollups
  * pushes every new alert to subscribed users (FCM is free)
  * marks nodes STALE/OFFLINE and raises NODE_OFFLINE alerts
  * re-sends unacknowledged alerts, then escalates to admins
  * applies role changes that admins request from the app (roleRequests)
  * deletes readings older than the retention period
  * writes a heartbeat the app shows when this service stops

Firestore usage is kept inside the free daily quota (20k writes, 50k reads):
open alerts are mirrored in memory from one listener instead of queried, the
last ThingSpeak entry per node is cached, and rollups are written hourly.

Run:  python -m forest_fire_backend.service
"""

from __future__ import annotations

import logging
import os
import signal
import threading
import time
from datetime import datetime, timedelta, timezone

import firebase_admin
from firebase_admin import auth, credentials, firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from .alert_rules import OPEN_STATUSES, decide_alert
from .notify import push_alert
from .risk import calculate_risk
from .rollup import HourBucket, HourlyAccumulator
from .thingspeak import fetch_last_feed, parse_feed

log = logging.getLogger("forest_fire_backend")

VERSION = "1.0.0"

POLL_SECONDS = int(os.getenv("POLL_SECONDS", "60"))
MAX_FEED_AGE_SECONDS = int(os.getenv("THINGSPEAK_MAX_AGE_SECONDS", "120"))
STALE_AFTER = timedelta(minutes=2)
OFFLINE_AFTER = timedelta(minutes=10)
ESCALATE_AFTER = timedelta(minutes=10)
#: Older unacknowledged alerts are left on the alerts screen, not re-pushed.
ESCALATION_MAX_AGE = timedelta(hours=6)
READING_RETENTION = timedelta(days=int(os.getenv("READING_RETENTION_DAYS", "30")))
#: Alerts older than this when first seen are not pushed (e.g. on restart).
PUSH_WINDOW = timedelta(minutes=15)

HEALTH_EVERY = 300
ESCALATION_EVERY = 300
HEARTBEAT_EVERY = 300
CHANNEL_RELOAD_EVERY = 300
LISTENER_REFRESH_EVERY = 1800
CLEANUP_EVERY = 6 * 3600

ROLES = ("viewer", "officer", "admin")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class BackendService:
    def __init__(self, db) -> None:
        self.db = db
        self.lock = threading.Lock()
        self.stopping = threading.Event()

        self.channels: list[dict] = []
        self.last_entry: dict[str, int | None] = {}
        self.node_locations: dict[str, tuple[float, float]] = {}
        self.open_alerts: dict[str, dict] = {}
        self.alert_active_written: dict[str, bool] = {}
        self.rollups = HourlyAccumulator()

        self._alert_watch = None
        self._role_watch = None
        self._next: dict[str, float] = {}

    # ------------------------------------------------------------------
    # Scheduling
    # ------------------------------------------------------------------

    def _due(self, name: str, every: float) -> bool:
        now = time.monotonic()
        if now >= self._next.get(name, 0):
            self._next[name] = now + every
            return True
        return False

    def _run(self, name: str, task) -> None:
        try:
            task()
        except Exception:  # keep the service alive; the next cycle retries
            log.exception("%s failed", name)

    def run_forever(self) -> None:
        log.info("Forest Fire backend %s starting (poll every %ss)", VERSION, POLL_SECONDS)

        while not self.stopping.is_set():
            if self._due("listeners", LISTENER_REFRESH_EVERY):
                self._run("listeners", self.start_listeners)
            if self._due("channels", CHANNEL_RELOAD_EVERY):
                self._run("channels", self.load_channels)
            if self._due("poll", POLL_SECONDS):
                self._run("poll", self.poll_all)
            if self._due("health", HEALTH_EVERY):
                self._run("health", self.check_node_health)
            if self._due("escalation", ESCALATION_EVERY):
                self._run("escalation", self.escalate_alerts)
            if self._due("heartbeat", HEARTBEAT_EVERY):
                self._run("heartbeat", self.write_heartbeat)
            if self._due("cleanup", CLEANUP_EVERY):
                self._run("cleanup", self.delete_old_readings)

            self.stopping.wait(1)

        self.shutdown()

    def shutdown(self) -> None:
        log.info("Shutting down; saving partial hourly rollups")
        for bucket in self.rollups.drain():
            self._run("rollup flush", lambda b=bucket: self.write_rollup(b))
        for watch in (self._alert_watch, self._role_watch):
            if watch is not None:
                watch.unsubscribe()

    # ------------------------------------------------------------------
    # Listeners
    # ------------------------------------------------------------------

    def start_listeners(self) -> None:
        """(Re)subscribes. Re-subscribing periodically guards against a watch
        that died silently; pushedAt prevents duplicate pushes."""
        for watch in (self._alert_watch, self._role_watch):
            if watch is not None:
                watch.unsubscribe()

        with self.lock:
            self.open_alerts.clear()

        self._alert_watch = (
            self.db.collection("alerts")
            .where(filter=FieldFilter("status", "in", list(OPEN_STATUSES)))
            .on_snapshot(self._on_open_alerts)
        )
        self._role_watch = (
            self.db.collection("roleRequests")
            .where(filter=FieldFilter("status", "==", "pending"))
            .on_snapshot(self._on_role_requests)
        )

    def _on_open_alerts(self, _docs, changes, _read_time) -> None:
        touched_nodes: set[str] = set()

        for change in changes:
            doc = change.document
            data = doc.to_dict() or {}
            node_id = str(data.get("deviceId", ""))
            touched_nodes.add(node_id)

            with self.lock:
                if change.type.name == "REMOVED":
                    self.open_alerts.pop(doc.id, None)
                    continue
                self.open_alerts[doc.id] = data

            if change.type.name == "ADDED" and self._needs_push(data):
                self._run("push", lambda i=doc.id, d=data: self._push_new_alert(i, d))

        for node_id in touched_nodes:
            self._run("alertActive", lambda n=node_id: self.refresh_alert_active(n))

    def _needs_push(self, data: dict) -> bool:
        if data.get("pushedAt") is not None or data.get("status") != "ACTIVE":
            return False
        detected = data.get("detectedAt")
        return isinstance(detected, datetime) and utcnow() - detected <= PUSH_WINDOW

    def _push_new_alert(self, alert_id: str, data: dict) -> None:
        push_alert(self.db, alert_id, data)
        self.db.collection("alerts").document(alert_id).update(
            {"pushedAt": firestore.SERVER_TIMESTAMP}
        )

    def refresh_alert_active(self, node_id: str) -> None:
        """Keeps devices/{node}.alertActive in step with open alerts, writing
        only when it changes."""
        if not node_id:
            return
        with self.lock:
            active = any(a.get("deviceId") == node_id for a in self.open_alerts.values())
            if self.alert_active_written.get(node_id) == active:
                return
            self.alert_active_written[node_id] = active

        self.db.collection("devices").document(node_id).set(
            {"alertActive": active}, merge=True
        )

    # ------------------------------------------------------------------
    # Ingestion
    # ------------------------------------------------------------------

    def load_channels(self) -> None:
        """Channel-to-node mapping from config/channels:
        {"channels": [{"nodeId": "NODE-01", "channelId": "3444282", "readApiKey"?, "name"?}]}"""
        doc = self.db.document("config/channels").get()
        channels = (doc.to_dict() or {}).get("channels") if doc.exists else None

        if not isinstance(channels, list):
            log.warning("config/channels is missing; nothing to poll")
            self.channels = []
            return

        self.channels = [
            c for c in channels if isinstance(c, dict) and c.get("nodeId") and c.get("channelId")
        ]

    def poll_all(self) -> None:
        now = utcnow()
        for channel in self.channels:
            self._run(f"ingest {channel['nodeId']}", lambda c=channel: self.ingest(c, now))

    def ingest(self, channel: dict, now: datetime) -> None:
        node_id = str(channel["nodeId"])
        device_ref = self.db.collection("devices").document(node_id)

        if node_id not in self.last_entry:
            # First poll since start: one read to learn the last entry and
            # location, then served from memory.
            snapshot = device_ref.get()
            data = snapshot.to_dict() or {}
            self.last_entry[node_id] = data.get("thingspeakEntryId")
            self.node_locations[node_id] = (data.get("latitude", 0), data.get("longitude", 0))
            if not snapshot.exists:
                device_ref.set({"deviceId": node_id, "name": channel.get("name", node_id)})

        feed = fetch_last_feed(str(channel["channelId"]), channel.get("readApiKey"))
        reading = parse_feed(feed, now, MAX_FEED_AGE_SECONDS)

        if reading.is_stale or (
            reading.entry_id is not None and reading.entry_id == self.last_entry.get(node_id)
        ):
            return  # nothing new; node health turns lastSeen age into STALE/OFFLINE

        risk = calculate_risk(
            reading.temperature,
            reading.humidity,
            reading.mq2_1,
            reading.mq2_2,
            reading.temperature2,
            reading.humidity2,
        )
        fire_probability = reading.ai_confidence * 100 if reading.fire_detected else 0.0

        batch = self.db.batch()
        batch.set(
            device_ref,
            {
                "deviceId": node_id,
                "status": "ONLINE",
                "lastSeen": reading.timestamp,
                "temperature": reading.temperature,
                "humidity": reading.humidity,
                "temperature2": reading.temperature2,
                "humidity2": reading.humidity2,
                "mq2Sensor1": reading.mq2_1,
                "mq2Sensor2": reading.mq2_2,
                "fireDetected": reading.fire_detected,
                "aiConfidence": reading.ai_confidence,
                "fireProbability": fire_probability,
                "smokeProbability": 0,
                "riskPoints": risk.points,
                "riskScore": risk.score,
                "riskLevel": risk.level,
                "thingspeakEntryId": reading.entry_id,
                "sensorDataAgeSeconds": reading.age_seconds,
                "sensorDataStale": False,
            },
            merge=True,
        )
        batch.set(
            device_ref.collection("readings").document(),
            {
                "ts": reading.timestamp,
                "temperature": reading.temperature,
                "humidity": reading.humidity,
                "temperature2": reading.temperature2,
                "humidity2": reading.humidity2,
                "mq2_1": reading.mq2_1,
                "mq2_2": reading.mq2_2,
                "fireProbability": fire_probability,
                "riskScore": risk.score,
                "entryId": reading.entry_id,
            },
        )
        batch.commit()
        self.last_entry[node_id] = reading.entry_id

        for bucket in self.rollups.add(
            node_id,
            reading.timestamp,
            temperature=reading.temperature,
            humidity=reading.humidity,
            smoke=max(reading.mq2_1, reading.mq2_2),
            fire_probability=fire_probability,
            risk_score=risk.score,
        ):
            self.write_rollup(bucket)

        decision = decide_alert(reading, risk.level)
        if decision:
            latitude, longitude = self.node_locations.get(node_id, (0, 0))
            self.create_alert_if_new(
                node_id,
                decision.type,
                decision.severity,
                {
                    "fireProbability": fire_probability,
                    "smokeProbability": 0,
                    "temperature": reading.temperature,
                    "humidity": reading.humidity,
                    "latitude": latitude,
                    "longitude": longitude,
                    "sensorReadings": {
                        "temperature2": reading.temperature2,
                        "humidity2": reading.humidity2,
                        "mq2_1": reading.mq2_1,
                        "mq2_2": reading.mq2_2,
                        "aiConfidence": reading.ai_confidence,
                        "entryId": reading.entry_id,
                    },
                },
            )

    def write_rollup(self, bucket: HourBucket) -> None:
        """Merges into any existing document for the hour, so a restart
        mid-hour adds to the partial bucket written before it."""
        ref = self.db.document(f"devices/{bucket.node_id}/hourly/{bucket.doc_id}")

        @firestore.transactional
        def merge(transaction):
            existing = ref.get(transaction=transaction).to_dict() or {}

            def peak(field, value):
                old = existing.get(field)
                if value is None:
                    return old
                return value if old is None else max(old, value)

            transaction.set(
                ref,
                {
                    "hour": bucket.hour,
                    "count": existing.get("count", 0) + bucket.count,
                    "temperatureSum": existing.get("temperatureSum", 0) + bucket.temperature_sum,
                    "humiditySum": existing.get("humiditySum", 0) + bucket.humidity_sum,
                    "smokeMax": peak("smokeMax", bucket.smoke_max),
                    "fireProbabilityMax": peak("fireProbabilityMax", bucket.fire_probability_max),
                    "riskScoreMax": peak("riskScoreMax", bucket.risk_score_max),
                },
            )

        merge(self.db.transaction())

    def create_alert_if_new(self, node_id: str, alert_type: str, severity: str, details: dict):
        """One alert per open condition, not one per reading. Uses the
        in-memory mirror of open alerts instead of a query."""
        with self.lock:
            for alert in self.open_alerts.values():
                if alert.get("deviceId") == node_id and alert.get("type") == alert_type:
                    return None

        alert_id = f"{node_id}_{alert_type}_{int(time.time())}"
        data = {
            "alertId": alert_id,
            "deviceId": node_id,
            "type": alert_type,
            "severity": severity,
            "status": "ACTIVE",
            "detectedAt": utcnow(),
            "escalationLevel": 0,
            **details,
        }

        # Record it locally first so the next reading can't raise a duplicate
        # before the listener catches up. The listener sees no pushedAt and
        # sends the push.
        with self.lock:
            self.open_alerts[alert_id] = data

        self.db.collection("alerts").document(alert_id).set(data)
        log.info("Alert created: %s (%s)", alert_id, severity)
        return alert_id

    # ------------------------------------------------------------------
    # Node health
    # ------------------------------------------------------------------

    def check_node_health(self) -> None:
        now = utcnow()

        for doc in self.db.collection("devices").stream():
            data = doc.to_dict() or {}
            last_seen = data.get("lastSeen")
            if not isinstance(last_seen, datetime):
                continue

            if "latitude" in data and "longitude" in data:
                self.node_locations[doc.id] = (data["latitude"], data["longitude"])

            # Also corrects alertActive left over from before a restart.
            self.refresh_alert_active(doc.id)

            age = now - last_seen
            status = "OFFLINE" if age > OFFLINE_AFTER else "STALE" if age > STALE_AFTER else "ONLINE"
            previous = data.get("status")

            if status == previous:
                continue

            doc.reference.update({"status": status})

            if status == "OFFLINE":
                self.create_alert_if_new(
                    doc.id,
                    "NODE_OFFLINE",
                    "HIGH",
                    {
                        "fireProbability": 0,
                        "smokeProbability": 0,
                        "temperature": data.get("temperature", 0),
                        "humidity": data.get("humidity", 0),
                        "latitude": data.get("latitude", 0),
                        "longitude": data.get("longitude", 0),
                    },
                )
            elif previous == "OFFLINE":
                self._resolve_outage_alerts(doc.id)

    def _resolve_outage_alerts(self, node_id: str) -> None:
        with self.lock:
            outages = [
                alert_id
                for alert_id, alert in self.open_alerts.items()
                if alert.get("deviceId") == node_id and alert.get("type") == "NODE_OFFLINE"
            ]

        for alert_id in outages:
            self.db.collection("alerts").document(alert_id).update(
                {
                    "status": "RESOLVED",
                    "resolvedBy": "system",
                    "resolvedByName": "System",
                    "resolvedAt": firestore.SERVER_TIMESTAMP,
                    "notes": "Node resumed reporting.",
                }
            )

    # ------------------------------------------------------------------
    # Escalation
    # ------------------------------------------------------------------

    def escalate_alerts(self) -> None:
        now = utcnow()

        with self.lock:
            candidates = list(self.open_alerts.items())

        for alert_id, data in candidates:
            if data.get("status") != "ACTIVE":
                continue

            detected = data.get("detectedAt")
            if not isinstance(detected, datetime):
                continue
            age = now - detected
            if age < ESCALATE_AFTER or age > ESCALATION_MAX_AGE:
                continue

            level = int(data.get("escalationLevel", 0) or 0)
            if level >= 2:
                continue

            escalated_at = data.get("escalatedAt")
            if isinstance(escalated_at, datetime) and now - escalated_at < ESCALATE_AFTER:
                continue

            next_level = level + 1
            push_alert(
                self.db, alert_id, data, admins_only=next_level == 2, escalation=next_level
            )

            # Update memory too, so a slow listener can't cause a repeat.
            with self.lock:
                if alert_id in self.open_alerts:
                    self.open_alerts[alert_id]["escalationLevel"] = next_level
                    self.open_alerts[alert_id]["escalatedAt"] = now

            self.db.collection("alerts").document(alert_id).update(
                {"escalationLevel": next_level, "escalatedAt": now}
            )

    # ------------------------------------------------------------------
    # Roles requested from the app by administrators
    # ------------------------------------------------------------------

    def _on_role_requests(self, _docs, changes, _read_time) -> None:
        for change in changes:
            if change.type.name == "ADDED":
                self._run(
                    "role request",
                    lambda d=change.document: self.apply_role_request(d.id, d.to_dict() or {}),
                )

    def apply_role_request(self, request_id: str, data: dict) -> None:
        ref = self.db.collection("roleRequests").document(request_id)

        def finish(status: str, message: str) -> None:
            ref.update(
                {"status": status, "message": message, "processedAt": firestore.SERVER_TIMESTAMP}
            )

        requester_uid = str(data.get("requestedBy", ""))
        email = str(data.get("email", "")).strip().lower()
        role = str(data.get("role", ""))

        try:
            requester = auth.get_user(requester_uid)
        except auth.UserNotFoundError:
            return finish("error", "Unknown requester.")

        # Security rules already require this; check again server-side.
        if (requester.custom_claims or {}).get("role") != "admin":
            return finish("error", "Only administrators can change roles.")
        if role not in ROLES:
            return finish("error", f"Role must be one of {', '.join(ROLES)}.")

        try:
            user = auth.get_user_by_email(email)
        except auth.UserNotFoundError:
            return finish("error", f"No account for {email}. Create it in Firebase Authentication first.")

        if user.uid == requester_uid and role != "admin":
            return finish("error", "You can't remove your own admin role.")

        set_role(self.db, user, role, changed_by=requester_uid)
        finish("done", f"{email} is now {role}.")

    # ------------------------------------------------------------------
    # Housekeeping
    # ------------------------------------------------------------------

    def delete_old_readings(self) -> None:
        """Retention without Firestore TTL policies. Deletes are counted
        separately from writes (20k/day free)."""
        cutoff = utcnow() - READING_RETENTION

        for node in self.db.collection("devices").list_documents():
            while True:
                old = list(
                    node.collection("readings")
                    .where(filter=FieldFilter("ts", "<", cutoff))
                    .limit(400)
                    .stream()
                )
                if not old:
                    break
                batch = self.db.batch()
                for doc in old:
                    batch.delete(doc.reference)
                batch.commit()
                log.info("Deleted %d old readings for %s", len(old), node.id)

    def write_heartbeat(self) -> None:
        with self.lock:
            open_count = len(self.open_alerts)

        self.db.document("status/backend").set(
            {
                "lastHeartbeat": firestore.SERVER_TIMESTAMP,
                "version": VERSION,
                "channels": len(self.channels),
                "openAlerts": open_count,
                "host": os.getenv("COMPUTERNAME") or os.getenv("HOSTNAME") or "unknown",
            }
        )


def set_role(db, user, role: str, changed_by: str | None = None) -> None:
    """Sets the custom claim (what security rules check) and mirrors it on the
    profile (used to find admins for escalation)."""
    auth.set_custom_user_claims(user.uid, {**(user.custom_claims or {}), "role": role})
    db.document(f"users/{user.uid}").set(
        {
            "email": user.email,
            "role": role,
            "roleUpdatedAt": firestore.SERVER_TIMESTAMP,
            "roleUpdatedBy": changed_by or "cli",
        },
        merge=True,
    )


def init_firebase():
    """Uses GOOGLE_APPLICATION_CREDENTIALS (a service-account key kept outside
    the repository)."""
    key = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
    if not key or not os.path.isfile(key):
        raise SystemExit(
            "Set GOOGLE_APPLICATION_CREDENTIALS to the path of a Firebase service-account "
            "key (Firebase console > Project settings > Service accounts > Generate new "
            "private key). Keep the key outside this repository."
        )

    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate(key))
    return firestore.client()


def main() -> None:
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    service = BackendService(init_firebase())

    def stop(*_):
        service.stopping.set()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    service.run_forever()


if __name__ == "__main__":
    main()
