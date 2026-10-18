import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { OPEN_STATUSES, decideAlert } from "./alertRules.js";
import { type AlertPayload, pushAlert } from "./notify.js";
import { calculateRisk } from "./risk.js";
import { fetchLastFeed, parseFeed } from "./thingspeak.js";

initializeApp();

// Asia South (Mumbai) is closest to the deployment; change with the project.
setGlobalOptions({ region: "asia-south1", maxInstances: 5 });

const db = getFirestore();

/** A node is STALE after this long without new data, OFFLINE after the next. */
const STALE_AFTER_MS = 2 * 60 * 1000;
const OFFLINE_AFTER_MS = 10 * 60 * 1000;
/** ThingSpeak entries older than this are not treated as live readings. */
const MAX_FEED_AGE_SECONDS = 120;
/** Unacknowledged alerts are re-sent after this, then escalated to admins. */
const ESCALATE_AFTER_MS = 10 * 60 * 1000;
const READING_RETENTION_DAYS = 30;

interface ChannelConfig {
  nodeId: string;
  channelId: string;
  readApiKey?: string;
  name?: string;
}

// ---------------------------------------------------------------------------
// INGESTION: ThingSpeak -> devices/{nodeId}, readings, hourly rollups, alerts
// ---------------------------------------------------------------------------

/**
 * Channel-to-node mapping lives in `config/channels`:
 *   { channels: [{ nodeId: "NODE-01", channelId: "3444282", readApiKey? }] }
 * The `config` collection is closed to app users by security rules.
 */
async function loadChannels(): Promise<ChannelConfig[]> {
  const doc = await db.doc("config/channels").get();
  const channels: unknown = doc.data()?.channels;

  if (!Array.isArray(channels)) {
    logger.warn("config/channels is missing; nothing to poll");
    return [];
  }

  return channels.filter(
    (c): c is ChannelConfig =>
      typeof c?.nodeId === "string" && typeof c?.channelId === "string",
  );
}

function hourKey(date: Date): string {
  return date.toISOString().slice(0, 13).replace(/[-T]/g, "");
}

async function ingestChannel(channel: ChannelConfig, now: Date): Promise<void> {
  const deviceRef = db.collection("devices").doc(channel.nodeId);
  const feed = await fetchLastFeed(channel.channelId, channel.readApiKey);
  const reading = parseFeed(feed, now, MAX_FEED_AGE_SECONDS);

  const device = await deviceRef.get();
  const lastEntry = device.data()?.thingspeakEntryId;

  if (reading.isStale || (reading.entryId != null && reading.entryId === lastEntry)) {
    // Nothing new. nodeHealth turns lastSeen age into STALE/OFFLINE.
    return;
  }

  const risk = calculateRisk({
    temperature: reading.temperature,
    humidity: reading.humidity,
    mq2_1: reading.mq2_1,
    mq2_2: reading.mq2_2,
    temperature2: reading.temperature2,
    humidity2: reading.humidity2,
  });

  const fireProbability = reading.fireDetected ? reading.aiConfidence * 100 : 0;
  const sensorTime = Timestamp.fromDate(reading.timestamp);

  await deviceRef.set(
    {
      deviceId: channel.nodeId,
      ...(device.exists ? {} : { name: channel.name ?? channel.nodeId }),
      status: "ONLINE",
      lastSeen: sensorTime,
      temperature: reading.temperature,
      humidity: reading.humidity,
      temperature2: reading.temperature2,
      humidity2: reading.humidity2,
      mq2Sensor1: reading.mq2_1,
      mq2Sensor2: reading.mq2_2,
      fireDetected: reading.fireDetected,
      aiConfidence: reading.aiConfidence,
      fireProbability,
      smokeProbability: 0,
      riskPoints: risk.points,
      riskScore: risk.score,
      riskLevel: risk.level,
      thingspeakEntryId: reading.entryId,
      sensorDataAgeSeconds: reading.ageSeconds,
      sensorDataStale: false,
    },
    { merge: true },
  );

  await deviceRef.collection("readings").add({
    ts: sensorTime,
    expireAt: Timestamp.fromMillis(
      reading.timestamp.getTime() + READING_RETENTION_DAYS * 86_400_000,
    ),
    temperature: reading.temperature,
    humidity: reading.humidity,
    temperature2: reading.temperature2,
    humidity2: reading.humidity2,
    mq2_1: reading.mq2_1,
    mq2_2: reading.mq2_2,
    fireProbability,
    riskScore: risk.score,
    entryId: reading.entryId,
  });

  await updateHourlyRollup(deviceRef.id, reading.timestamp, {
    temperature: reading.temperature,
    humidity: reading.humidity,
    smoke: Math.max(reading.mq2_1, reading.mq2_2),
    fireProbability,
    riskScore: risk.score,
  });

  const decision = decideAlert(reading, risk.level);
  if (decision) {
    await createAlertIfNew(channel.nodeId, decision.type, decision.severity, {
      fireProbability,
      smokeProbability: 0,
      temperature: reading.temperature,
      humidity: reading.humidity,
      latitude: device.data()?.latitude ?? 0,
      longitude: device.data()?.longitude ?? 0,
      sensorReadings: {
        temperature2: reading.temperature2,
        humidity2: reading.humidity2,
        mq2_1: reading.mq2_1,
        mq2_2: reading.mq2_2,
        aiConfidence: reading.aiConfidence,
        entryId: reading.entryId,
      },
    });
  }
}

async function updateHourlyRollup(
  nodeId: string,
  time: Date,
  values: {
    temperature: number;
    humidity: number;
    smoke: number;
    fireProbability: number;
    riskScore: number;
  },
): Promise<void> {
  const hour = new Date(time);
  hour.setUTCMinutes(0, 0, 0);
  const ref = db.doc(`devices/${nodeId}/hourly/${hourKey(hour)}`);

  await db.runTransaction(async (tx) => {
    const current = (await tx.get(ref)).data() ?? {};
    const max = (field: string, value: number) =>
      Math.max(typeof current[field] === "number" ? current[field] : value, value);

    tx.set(
      ref,
      {
        hour: Timestamp.fromDate(hour),
        count: FieldValue.increment(1),
        temperatureSum: FieldValue.increment(values.temperature),
        humiditySum: FieldValue.increment(values.humidity),
        smokeMax: max("smokeMax", values.smoke),
        fireProbabilityMax: max("fireProbabilityMax", values.fireProbability),
        riskScoreMax: max("riskScoreMax", values.riskScore),
      },
      { merge: true },
    );
  });
}

/**
 * Creates an alert unless the node already has an open one of the same type,
 * so a sustained condition raises one alert rather than one per minute.
 */
async function createAlertIfNew(
  nodeId: string,
  type: string,
  severity: string,
  details: Record<string, unknown>,
): Promise<string | null> {
  const open = await db
    .collection("alerts")
    .where("deviceId", "==", nodeId)
    .where("type", "==", type)
    .where("status", "in", OPEN_STATUSES)
    .limit(1)
    .get();

  if (!open.empty) {
    return null;
  }

  const alertId = `${nodeId}_${type}_${Date.now()}`;
  await db.collection("alerts").doc(alertId).set({
    alertId,
    deviceId: nodeId,
    type,
    severity,
    status: "ACTIVE",
    detectedAt: FieldValue.serverTimestamp(),
    escalationLevel: 0,
    ...details,
  });

  logger.info("Alert created", { alertId, severity });
  return alertId;
}

export const pollThingSpeak = onSchedule(
  { schedule: "every 1 minutes", timeoutSeconds: 50 },
  async () => {
    const channels = await loadChannels();
    const now = new Date();

    const results = await Promise.allSettled(
      channels.map((channel) => ingestChannel(channel, now)),
    );

    results.forEach((result, index) => {
      if (result.status === "rejected") {
        logger.error("Ingestion failed", {
          nodeId: channels[index].nodeId,
          error: String(result.reason),
        });
      }
    });
  },
);

// ---------------------------------------------------------------------------
// NODE HEALTH: lastSeen age -> ONLINE / STALE / OFFLINE, alert on OFFLINE
// ---------------------------------------------------------------------------

export const nodeHealth = onSchedule("every 5 minutes", async () => {
  const now = Date.now();
  const devices = await db.collection("devices").get();

  await Promise.all(
    devices.docs.map(async (doc) => {
      const data = doc.data();
      const lastSeen: Timestamp | undefined = data.lastSeen;
      if (!lastSeen) return;

      const age = now - lastSeen.toMillis();
      const status = age > OFFLINE_AFTER_MS ? "OFFLINE" : age > STALE_AFTER_MS ? "STALE" : "ONLINE";

      if (status === data.status) return;

      await doc.ref.update({ status });

      if (status === "OFFLINE") {
        await createAlertIfNew(doc.id, "NODE_OFFLINE", "HIGH", {
          fireProbability: 0,
          smokeProbability: 0,
          temperature: data.temperature ?? 0,
          humidity: data.humidity ?? 0,
          latitude: data.latitude ?? 0,
          longitude: data.longitude ?? 0,
        });
      } else if (data.status === "OFFLINE") {
        // Back online: close the outage alert so it doesn't linger.
        const outages = await db
          .collection("alerts")
          .where("deviceId", "==", doc.id)
          .where("type", "==", "NODE_OFFLINE")
          .where("status", "in", OPEN_STATUSES)
          .get();

        await Promise.all(
          outages.docs.map((alert) =>
            alert.ref.update({
              status: "RESOLVED",
              resolvedBy: "system",
              resolvedByName: "System",
              resolvedAt: FieldValue.serverTimestamp(),
              notes: "Node resumed reporting.",
            }),
          ),
        );
      }
    }),
  );
});

// ---------------------------------------------------------------------------
// PUSH: every new alert, from this backend or the Python bridge
// ---------------------------------------------------------------------------

function toPayload(id: string, data: FirebaseFirestore.DocumentData): AlertPayload {
  return {
    alertId: id,
    deviceId: String(data.deviceId ?? ""),
    type: String(data.type ?? "FIRE ALERT"),
    severity: String(data.severity ?? "HIGH"),
    fireProbability: Number(data.fireProbability ?? 0),
    smokeProbability: Number(data.smokeProbability ?? 0),
    temperature: Number(data.temperature ?? 0),
    humidity: Number(data.humidity ?? 0),
  };
}

async function refreshAlertActive(nodeId: string): Promise<void> {
  if (!nodeId) return;

  const open = await db
    .collection("alerts")
    .where("deviceId", "==", nodeId)
    .where("status", "in", OPEN_STATUSES)
    .limit(1)
    .get();

  await db.doc(`devices/${nodeId}`).set({ alertActive: !open.empty }, { merge: true });
}

export const onAlertCreated = onDocumentCreated("alerts/{alertId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  await Promise.all([
    pushAlert(toPayload(event.params.alertId, data), { nodeId: data.deviceId }),
    refreshAlertActive(String(data.deviceId ?? "")),
  ]);
});

export const onAlertUpdated = onDocumentUpdated("alerts/{alertId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();

  if (!before || !after || before.status === after.status) return;

  await refreshAlertActive(String(after.deviceId ?? ""));
});

// ---------------------------------------------------------------------------
// ESCALATION: unacknowledged alerts are re-sent, then sent to admins
// ---------------------------------------------------------------------------

export const escalateAlerts = onSchedule("every 5 minutes", async () => {
  const cutoff = Timestamp.fromMillis(Date.now() - ESCALATE_AFTER_MS);

  const overdue = await db
    .collection("alerts")
    .where("status", "==", "ACTIVE")
    .where("detectedAt", "<=", cutoff)
    .get();

  await Promise.all(
    overdue.docs.map(async (doc) => {
      const data = doc.data();
      const level = Number(data.escalationLevel ?? 0);
      if (level >= 2) return;

      const lastEscalated: Timestamp | undefined = data.escalatedAt;
      if (lastEscalated && Date.now() - lastEscalated.toMillis() < ESCALATE_AFTER_MS) {
        return;
      }

      const next = level + 1;
      await pushAlert(
        toPayload(doc.id, data),
        next === 1 ? { nodeId: data.deviceId } : { adminsOnly: true },
        next,
      );

      await doc.ref.update({
        escalationLevel: next,
        escalatedAt: FieldValue.serverTimestamp(),
      });
    }),
  );
});

// ---------------------------------------------------------------------------
// ROLES: admins grant viewer / officer / admin
// ---------------------------------------------------------------------------

const ROLES = ["viewer", "officer", "admin"] as const;
type Role = (typeof ROLES)[number];

export const setUserRole = onCall(async (request) => {
  if (request.auth?.token.role !== "admin") {
    throw new HttpsError("permission-denied", "Only administrators can change roles.");
  }

  const email = String(request.data?.email ?? "").trim().toLowerCase();
  const role = String(request.data?.role ?? "") as Role;

  if (!email.includes("@")) {
    throw new HttpsError("invalid-argument", "A valid email is required.");
  }
  if (!ROLES.includes(role)) {
    throw new HttpsError("invalid-argument", `Role must be one of ${ROLES.join(", ")}.`);
  }

  let user;
  try {
    user = await getAuth().getUserByEmail(email);
  } catch {
    throw new HttpsError(
      "not-found",
      `No account for ${email}. Create it in Firebase Authentication first.`,
    );
  }

  if (user.uid === request.auth.uid && role !== "admin") {
    throw new HttpsError("failed-precondition", "You can't remove your own admin role.");
  }

  await getAuth().setCustomUserClaims(user.uid, { ...user.customClaims, role });

  // Mirror the role for push targeting (escalation to admins); the claim
  // remains the source of truth for permissions.
  await db.doc(`users/${user.uid}`).set(
    {
      email,
      role,
      roleUpdatedAt: FieldValue.serverTimestamp(),
      roleUpdatedBy: request.auth.uid,
    },
    { merge: true },
  );

  logger.info("Role changed", { uid: user.uid, role, by: request.auth.uid });
  return { uid: user.uid, role };
});
