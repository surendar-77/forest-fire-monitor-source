/** Push alerts through FCM HTTP v1 (free on every Firebase plan). */

import type { Firestore, Plain } from "./firestore.js";

/** Must match NotificationService._channelId in the Flutter app. */
const ANDROID_CHANNEL_ID = "forest_fire_alerts";

export interface PushOptions {
  adminsOnly?: boolean;
  escalation?: number;
  /** Most sends allowed in this invocation (Workers Free: 50 subrequests). */
  maxSends: number;
}

type Alert = Record<string, Plain>;

function title(alert: Alert, escalation: number): string {
  const prefix = escalation > 0 ? "UNACKNOWLEDGED: " : "";
  const kind =
    alert.type === "NODE_OFFLINE"
      ? "Node offline"
      : alert.type === "FIRE"
        ? "Fire detected"
        : alert.type === "SMOKE"
          ? "Smoke detected"
          : "High fire risk";
  return `${prefix}${alert.severity ?? "HIGH"} · ${kind} at ${alert.deviceId ?? "?"}`;
}

function body(alert: Alert): string {
  if (alert.type === "NODE_OFFLINE") {
    return `${alert.deviceId} has stopped reporting. Check power and connectivity.`;
  }
  const parts: string[] = [];
  if (typeof alert.temperature === "number") parts.push(`${alert.temperature.toFixed(1)}°C`);
  if (typeof alert.humidity === "number") parts.push(`${alert.humidity.toFixed(0)}% RH`);
  if (typeof alert.fireProbability === "number" && alert.fireProbability > 0) {
    parts.push(`fire ${alert.fireProbability.toFixed(0)}%`);
  }
  return `${parts.join(" · ")}. Open the app to acknowledge.`;
}

/**
 * Sends the alert to every device of every user in the audience. Users with
 * an empty `subscribedNodes` list get alerts from all nodes. Dead tokens are
 * deleted. Returns the number of devices reached.
 */
export async function pushAlert(
  fs: Firestore,
  projectId: string,
  token: () => Promise<string>,
  alertId: string,
  alert: Alert,
  options: PushOptions,
): Promise<number> {
  const escalation = options.escalation ?? 0;
  const [users, tokens] = await Promise.all([fs.query("users"), fs.query("pushTokens")]);

  const audience = new Set(
    users
      .filter((user) => {
        if (options.adminsOnly) return user.data.role === "admin";
        const nodes = user.data.subscribedNodes;
        return !Array.isArray(nodes) || nodes.length === 0 || nodes.includes(alert.deviceId);
      })
      .map((user) => user.id),
  );

  // Users who never opened their profile have no users/{uid} document yet;
  // they still get node alerts (but never admin escalations).
  const known = new Set(users.map((user) => user.id));
  const targets = tokens.filter((t) => {
    const uid = String(t.data.uid ?? "");
    return audience.has(uid) || (!options.adminsOnly && !known.has(uid));
  });

  if (targets.length === 0) {
    console.warn(`No push tokens for alert ${alertId}`);
    return 0;
  }

  if (targets.length > options.maxSends) {
    console.warn(`Alert ${alertId}: ${targets.length} devices, sending to first ${options.maxSends}`);
  }

  const severity = String(alert.severity ?? "HIGH");
  const urgent = severity === "HIGH" || severity === "CRITICAL";
  const data: Record<string, string> = {
    alertId,
    deviceId: String(alert.deviceId ?? ""),
    type: String(alert.type ?? ""),
    severity,
    fireProbability: String(alert.fireProbability ?? 0),
    smokeProbability: String(alert.smokeProbability ?? 0),
    temperature: String(alert.temperature ?? 0),
    humidity: String(alert.humidity ?? 0),
    escalation: String(escalation),
  };

  const bearer = await token();
  const results = await Promise.all(
    targets.slice(0, options.maxSends).map(async (target) => {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            message: {
              token: target.id,
              notification: { title: title(alert, escalation), body: body(alert) },
              data,
              android: {
                priority: "HIGH",
                notification: { channel_id: ANDROID_CHANNEL_ID, sound: "default", tag: alertId },
              },
              apns: {
                headers: { "apns-priority": "10" },
                payload: {
                  aps: { sound: "default", "interruption-level": urgent ? "time-sensitive" : "active" },
                },
              },
              webpush: {
                headers: { Urgency: urgent ? "high" : "normal" },
                notification: { requireInteraction: urgent, tag: alertId },
              },
            },
          }),
        },
      );

      if (response.ok) return { target, ok: true, dead: false };

      const text = await response.text();
      const dead =
        response.status === 404 || text.includes("UNREGISTERED") || text.includes("INVALID_ARGUMENT");
      if (!dead) console.warn(`Push failed for ${alertId}: ${response.status} ${text}`);
      return { target, ok: false, dead };
    }),
  );

  const dead = results.filter((r) => r.dead).map((r) => ({ delete: r.target.path }));
  if (dead.length > 0) await fs.commit(dead);

  const delivered = results.filter((r) => r.ok).length;
  console.log(`Alert ${alertId} pushed to ${delivered}/${targets.length} devices (escalation ${escalation})`);
  return delivered;
}
