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
