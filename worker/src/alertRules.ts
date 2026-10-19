import type { AnomalyResult } from "./anomaly.js";
import type { SensorReading } from "./thingspeak.js";

export interface AlertDecision {
  type: "FIRE" | "SMOKE" | "SENSOR_ANOMALY";
  severity: "MODERATE" | "HIGH" | "CRITICAL";
}

export const AI_FIRE_CONFIDENCE_THRESHOLD = 0.5;

const HIGH_DANGER = new Set(["HIGH", "VERY HIGH"]);

/**
 * Whether a reading should raise an alert, from the ML signals only:
 * the camera model (ThingSpeak fields 7/8), the node's smoke/heat anomaly
 * score against its learned baseline, and today's fire-danger rating, which
 * raises severity when conditions favour spread.
 */
export function decideAlert(
  reading: SensorReading,
  anomaly: AnomalyResult,
  dangerLevel: string | null,
): AlertDecision | null {
  const confident = reading.aiConfidence >= AI_FIRE_CONFIDENCE_THRESHOLD;
  const sensorsAgree = anomaly.level === "SUSPICIOUS" || anomaly.level === "LIKELY";
  const highDanger = dangerLevel != null && HIGH_DANGER.has(dangerLevel);

  if (reading.fireDetected && confident) {
    return { type: "FIRE", severity: sensorsAgree || highDanger ? "CRITICAL" : "HIGH" };
  }

  if (reading.smokeDetected && confident) {
    return { type: "SMOKE", severity: sensorsAgree || highDanger ? "HIGH" : "MODERATE" };
  }

  if (anomaly.level === "LIKELY") {
    return { type: "SENSOR_ANOMALY", severity: highDanger ? "CRITICAL" : "HIGH" };
  }

  return null;
}

/** Alerts that still need someone's attention. */
export const OPEN_STATUSES = ["ACTIVE", "ACKNOWLEDGED"];

/** An open alert this recent still covers a new detection of the same type. */
export const ACTIVE_DEDUPE_MS = 10 * 60_000;
/** Someone is handling it: hold off repeats for longer. */
export const ACKNOWLEDGED_DEDUPE_MS = 30 * 60_000;

function asTime(value: unknown): number | null {
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") {
    const t = Date.parse(value);
    return Number.isNaN(t) ? null : t;
  }
  return null;
}

/**
 * Whether an open alert should stop a new alert for a fresh detection
 * (fire, smoke, sensor anomaly). Only recent ones do: an alert nobody
 * resolved days ago must never silence a new fire. Alerts with no usable
 * time are treated as old.
 */
export function blocksNewDetection(alert: Record<string, unknown>, now: Date): boolean {
  const status = alert.status;
  const detected = asTime(alert.detectedAt) ?? asTime(alert.timestamp) ?? asTime(alert.createdAt);
  if (status === "ACKNOWLEDGED") {
    const since = asTime(alert.acknowledgedAt) ?? detected;
    return since != null && now.getTime() - since < ACKNOWLEDGED_DEDUPE_MS;
  }
  if (status === "ACTIVE") return detected != null && now.getTime() - detected < ACTIVE_DEDUPE_MS;
  return false;
}
