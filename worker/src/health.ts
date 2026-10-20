/**
 * Sensor-problem alerts from the board's health report (RTDB
 * health/{node}/info, sent every 30 s): camera gone, a dead sensor, a power
 * brownout, weak Wi-Fi, low battery, an overheating chip. A problem must
 * last a while before it alerts (one bad sample is not a fault), and its
 * alert resolves itself once the problem clears.
 */

import type { Plain } from "./firestore.js";

export const HEALTH_ALERT_TYPES = [
  "CAMERA_OFFLINE",
  "SENSOR_FAULT",
  "POWER_PROBLEM",
  "WEAK_WIFI",
  "LOW_BATTERY",
  "BOARD_HOT",
] as const;
export type HealthAlertType = (typeof HEALTH_ALERT_TYPES)[number];

export function isHealthAlert(type: unknown): boolean {
  return HEALTH_ALERT_TYPES.includes(type as HealthAlertType);
}

/** A report older than this says nothing about the board now. */
export const HEALTH_FRESH_MS = 3 * 60_000;

export interface HealthInfo {
  time: Date | null;
  uptimeSeconds: number | null;
  restartReason: string | null;
  starts: number | null;
  rssi: number | null;
  battery: number | null;
  chipTemperature: number | null;
  cameraAgeSeconds: number | null;
  dht1: boolean | null;
  dht2: boolean | null;
  smokeSensor: string | null;
}

const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);
const bool = (v: unknown): boolean | null => (typeof v === "boolean" ? v : null);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

/** The RTDB JSON of health/{node}/info, or null when absent. */
export function parseHealth(raw: unknown): HealthInfo | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  const ts = num(r.ts);
  return {
    time: ts == null ? null : new Date(ts),
    uptimeSeconds: num(r.up),
    restartReason: str(r.boot),
    starts: num(r.boots),
    rssi: num(r.rssi),
    battery: num(r.bat),
    chipTemperature: num(r.chipT),
    cameraAgeSeconds: num(r.camAge),
    dht1: bool(r.dht1),
    dht2: bool(r.dht2),
    smokeSensor: str(r.mq),
  };
}

export interface HealthIssue {
  type: HealthAlertType;
  severity: "LOW" | "MODERATE" | "HIGH";
  message: string;
  /** How long it must last before it alerts. */
  afterMs: number;
}

const MIN = 60_000;

/** Problems visible in this report (the brownout restart is handled apart). */
export function currentIssues(h: HealthInfo): HealthIssue[] {
  const issues: HealthIssue[] = [];

  const camAge = h.cameraAgeSeconds;
  const upFor = h.uptimeSeconds ?? 0;
  if ((camAge != null && camAge >= 600) || (camAge === -1 && upFor >= 600)) {
    const minutes = Math.round((camAge != null && camAge > 0 ? camAge : upFor) / 60);
    issues.push({
      type: "CAMERA_OFFLINE",
      severity: "MODERATE",
      message: `No camera photo for ${minutes} min. Check the camera's power and that it is near the sensor board.`,
      afterMs: 0,
    });
  }

  const broken: string[] = [];
  if (h.dht1 === false) broken.push("temperature/humidity sensor 1");
  if (h.dht2 === false) broken.push("temperature/humidity sensor 2");
  if (h.smokeSensor != null && /^MQ\d?.*faulty/i.test(h.smokeSensor)) broken.push(`smoke sensor (${h.smokeSensor})`);
  if (broken.length > 0) {
    issues.push({
      type: "SENSOR_FAULT",
      severity: "MODERATE",
      message: `Not reading: ${broken.join(", ")}. Check its wires.`,
      afterMs: 10 * MIN,
    });
  }

  if (h.rssi != null && h.rssi < -80) {
    issues.push({
      type: "WEAK_WIFI",
      severity: "LOW",
      message: `Wi-Fi signal is weak (${h.rssi} dBm). Uploads may fail; move the router or sensor closer.`,
      afterMs: 15 * MIN,
    });
  }

  if (h.battery != null && h.battery <= 20) {
    issues.push({
      type: "LOW_BATTERY",
      severity: h.battery <= 10 ? "HIGH" : "MODERATE",
      message: `Battery at ${Math.round(h.battery)}%. Charge or replace it soon.`,
      afterMs: 5 * MIN,
    });
  }

  if (h.chipTemperature != null && h.chipTemperature >= 80) {
    issues.push({
      type: "BOARD_HOT",
      severity: "MODERATE",
      message: `Board chip at ${Math.round(h.chipTemperature)} °C. Shade and ventilate the box.`,
      afterMs: 10 * MIN,
    });
  }

  return issues;
}

export interface HealthPlan {
  /** When each current problem was first seen (store on the device). */
  since: Record<string, Date>;
  /** Problems to alert about (duplicates are dropped by the caller). */
  raise: HealthIssue[];
  /** Types whose open alerts should resolve: the problem is gone. */
  clear: HealthAlertType[];
  /** Start number of a brownout restart just alerted about. */
  brownoutStart: number | null;
}

/**
 * Compares this report with what was seen before. Returns null when the
 * report is too old to judge (the node is probably offline, which has its
 * own alert).
 */
export function planHealth(
  h: HealthInfo,
  now: Date,
  previousSince: Record<string, Plain> | null | undefined,
  lastBrownoutStart: number | null,
): HealthPlan | null {
  if (!h.time || now.getTime() - h.time.getTime() > HEALTH_FRESH_MS) return null;

  const issues = currentIssues(h);
  const since: Record<string, Date> = {};
  for (const issue of issues) {
    const before = previousSince?.[issue.type];
    since[issue.type] = before instanceof Date ? before : now;
  }

  const raise = issues.filter((issue) => now.getTime() - since[issue.type].getTime() >= issue.afterMs);

  let brownoutStart: number | null = null;
  if (h.restartReason === "brownout" && h.starts != null && h.starts !== lastBrownoutStart) {
    brownoutStart = h.starts;
    raise.push({
      type: "POWER_PROBLEM",
      severity: "MODERATE",
      message:
        "The sensor restarted because its power dipped too low. Use a 5 V 2 A adapter and a short, good USB cable.",
      afterMs: 0,
    });
  }

  const present = new Set(issues.map((issue) => issue.type));
  const clear = HEALTH_ALERT_TYPES.filter((type) => type !== "POWER_PROBLEM" && !present.has(type));

  return { since, raise, clear, brownoutStart };
}
