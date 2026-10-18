"""Push alerts to every phone and browser a user is signed in on.

FCM is free on every Firebase plan, including Spark.
"""

from __future__ import annotations

import logging

from firebase_admin import exceptions, messaging
from google.cloud.firestore_v1.client import Client

log = logging.getLogger(__name__)

#: Must match NotificationService._channelId in the Flutter app.
ANDROID_CHANNEL_ID = "forest_fire_alerts"
MULTICAST_LIMIT = 500


def _collect_tokens(db: Client, node_id: str | None, admins_only: bool) -> list[tuple[str, str]]:
    """(token, document path) for every device of every user in the audience.
    Users with no profile document yet get node alerts but not escalations."""
    profiles = {user.id: user.to_dict() or {} for user in db.collection("users").stream()}
    refs: list[tuple[str, str]] = []

    for token in db.collection("pushTokens").stream():
        uid = str((token.to_dict() or {}).get("uid", ""))
        profile = profiles.get(uid)

        if admins_only:
            if not profile or profile.get("role") != "admin":
                continue
        elif profile is not None:
            subscribed = profile.get("subscribedNodes")
            if node_id and isinstance(subscribed, list) and subscribed and node_id not in subscribed:
                continue

        refs.append((token.id, token.reference.path))

    return refs


def _title(alert: dict, escalation: int) -> str:
    prefix = "UNACKNOWLEDGED: " if escalation > 0 else ""
    kind = {
        "NODE_OFFLINE": "Node offline",
        "FIRE": "Fire detected",
        "SMOKE": "Smoke detected",
    }.get(alert.get("type"), "High fire risk")
    return f"{prefix}{alert.get('severity', 'HIGH')} · {kind} at {alert.get('deviceId', '?')}"


def _body(alert: dict) -> str:
    if alert.get("type") == "NODE_OFFLINE":
        return f"{alert.get('deviceId')} has stopped reporting. Check power and connectivity."

    parts = []
    if alert.get("temperature") is not None:
        parts.append(f"{float(alert['temperature']):.1f}°C")
    if alert.get("humidity") is not None:
        parts.append(f"{float(alert['humidity']):.0f}% RH")
    if alert.get("fireProbability"):
        parts.append(f"fire {float(alert['fireProbability']):.0f}%")
    return f"{' · '.join(parts)}. Open the app to acknowledge."


def push_alert(
    db: Client,
    alert_id: str,
    alert: dict,
    *,
    admins_only: bool = False,
    escalation: int = 0,
) -> int:
    """Sends the alert and removes tokens FCM reports as dead. Returns the
    number of devices it reached."""
    node_id = None if admins_only else alert.get("deviceId")
    tokens = _collect_tokens(db, node_id, admins_only)

    if not tokens:
        log.warning("No push tokens for alert %s", alert_id)
        return 0

    severity = str(alert.get("severity", "HIGH"))
    urgent = severity in ("HIGH", "CRITICAL")
    data = {
        "alertId": alert_id,
        "deviceId": str(alert.get("deviceId", "")),
        "type": str(alert.get("type", "")),
        "severity": severity,
        "fireProbability": str(alert.get("fireProbability", 0)),
        "smokeProbability": str(alert.get("smokeProbability", 0)),
        "temperature": str(alert.get("temperature", 0)),
        "humidity": str(alert.get("humidity", 0)),
        "escalation": str(escalation),
    }

    delivered = 0
    for start in range(0, len(tokens), MULTICAST_LIMIT):
        batch = tokens[start : start + MULTICAST_LIMIT]
        message = messaging.MulticastMessage(
            tokens=[token for token, _ in batch],
            notification=messaging.Notification(title=_title(alert, escalation), body=_body(alert)),
            data=data,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id=ANDROID_CHANNEL_ID, sound="default", tag=alert_id
                ),
            ),
            apns=messaging.APNSConfig(
                headers={"apns-priority": "10"},
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        sound="default",
                        custom_data={
                            "interruption-level": "time-sensitive" if urgent else "active"
                        },
                    )
                ),
            ),
            webpush=messaging.WebpushConfig(
                headers={"Urgency": "high" if urgent else "normal"},
                notification=messaging.WebpushNotification(
                    require_interaction=urgent, tag=alert_id
                ),
            ),
        )

        response = messaging.send_each_for_multicast(message)
        delivered += response.success_count

        for (_, path), result in zip(batch, response.responses):
            error = result.exception
            if isinstance(error, (messaging.UnregisteredError, exceptions.InvalidArgumentError)):
                db.document(path).delete()
            elif error is not None:
                log.warning("Push failed for alert %s: %s", alert_id, error)

    log.info(
        "Alert %s pushed to %d/%d devices (escalation %d)",
        alert_id,
        delivered,
        len(tokens),
        escalation,
    )
    return delivered
