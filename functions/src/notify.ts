import { getFirestore } from "firebase-admin/firestore";
import { getMessaging, type MulticastMessage } from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";

/** Must match NotificationService._channelId in the Flutter app. */
const ANDROID_CHANNEL_ID = "forest_fire_alerts";

const MULTICAST_LIMIT = 500;

export interface AlertPayload {
  alertId: string;
  deviceId: string;
  type: string;
  severity: string;
  fireProbability?: number;
  smokeProbability?: number;
  temperature?: number;
  humidity?: number;
}

export interface Audience {
  /** Only users subscribed to this node (or to all nodes). */
  nodeId?: string;
  /** Only administrators (used for escalation). */
  adminsOnly?: boolean;
}

interface TokenRef {
  token: string;
  path: string;
}

/** Push tokens of every user in the audience. */
async function collectTokens(audience: Audience): Promise<TokenRef[]> {
  const db = getFirestore();
  const users = await db.collection("users").get();
  const refs: TokenRef[] = [];

  await Promise.all(
    users.docs.map(async (user) => {
      const data = user.data();
      const subscribed: unknown = data.subscribedNodes;

      if (audience.adminsOnly && data.role !== "admin") return;

      if (
        audience.nodeId &&
        Array.isArray(subscribed) &&
        subscribed.length > 0 &&
        !subscribed.includes(audience.nodeId)
      ) {
        return;
      }

      const tokens = await user.ref.collection("tokens").get();
      for (const doc of tokens.docs) {
        refs.push({ token: doc.id, path: doc.ref.path });
      }
    }),
  );

  return refs;
}

function titleFor(alert: AlertPayload, escalation: number): string {
  const prefix = escalation > 0 ? "UNACKNOWLEDGED: " : "";
  const kind =
    alert.type === "NODE_OFFLINE"
      ? "Node offline"
      : alert.type === "FIRE"
        ? "Fire detected"
        : alert.type === "SMOKE"
          ? "Smoke detected"
          : "High fire risk";
  return `${prefix}${alert.severity} · ${kind} at ${alert.deviceId}`;
}

function bodyFor(alert: AlertPayload): string {
  if (alert.type === "NODE_OFFLINE") {
    return `${alert.deviceId} has stopped reporting. Check power and connectivity.`;
  }

  const parts: string[] = [];
  if (alert.temperature != null) parts.push(`${alert.temperature.toFixed(1)}°C`);
  if (alert.humidity != null) parts.push(`${alert.humidity.toFixed(0)}% RH`);
  if (alert.fireProbability) parts.push(`fire ${alert.fireProbability.toFixed(0)}%`);
  return `${parts.join(" · ")}. Open the app to acknowledge.`;
}

/**
 * Sends an alert to every phone and browser in the audience and removes
 * tokens that FCM reports as no longer valid. Returns the number delivered.
 */
export async function pushAlert(
  alert: AlertPayload,
  audience: Audience,
  escalation = 0,
): Promise<number> {
  const tokens = await collectTokens(audience);

  if (tokens.length === 0) {
    logger.warn("No push tokens for alert", { alertId: alert.alertId, audience });
    return 0;
  }

  const title = titleFor(alert, escalation);
  const body = bodyFor(alert);
  const data: Record<string, string> = {
    alertId: alert.alertId,
    deviceId: alert.deviceId,
    type: alert.type,
    severity: alert.severity,
    fireProbability: String(alert.fireProbability ?? 0),
    smokeProbability: String(alert.smokeProbability ?? 0),
    temperature: String(alert.temperature ?? 0),
    humidity: String(alert.humidity ?? 0),
    escalation: String(escalation),
  };

  const urgent = alert.severity === "CRITICAL" || alert.severity === "HIGH";
  const messaging = getMessaging();
  const db = getFirestore();
  let delivered = 0;

  for (let i = 0; i < tokens.length; i += MULTICAST_LIMIT) {
    const batch = tokens.slice(i, i + MULTICAST_LIMIT);
    const message: MulticastMessage = {
      tokens: batch.map((ref) => ref.token),
      notification: { title, body },
      data,
      android: {
        priority: "high",
        notification: {
          channelId: ANDROID_CHANNEL_ID,
          sound: "default",
          tag: alert.alertId,
        },
      },
      apns: {
        headers: { "apns-priority": "10" },
        payload: {
          aps: {
            sound: "default",
            "interruption-level": urgent ? "time-sensitive" : "active",
          },
        },
      },
      webpush: {
        headers: { Urgency: urgent ? "high" : "normal" },
        notification: { requireInteraction: urgent, tag: alert.alertId },
      },
    };

    const response = await messaging.sendEachForMulticast(message);
    delivered += response.successCount;

    const stale: Promise<unknown>[] = [];
    response.responses.forEach((result, index) => {
      const code = result.error?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token" ||
        code === "messaging/invalid-argument"
      ) {
        stale.push(db.doc(batch[index].path).delete());
      } else if (result.error) {
        logger.warn("Push failed", { code, alertId: alert.alertId });
      }
    });
    await Promise.all(stale);
  }

  logger.info("Alert pushed", {
    alertId: alert.alertId,
    tokens: tokens.length,
    delivered,
    escalation,
  });
  return delivered;
}
