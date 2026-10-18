import type { RiskLevel } from "./risk.js";
import type { SensorReading } from "./thingspeak.js";

export interface AlertDecision {
  type: "FIRE" | "ENVIRONMENTAL_RISK";
  severity: RiskLevel;
}

export const AI_FIRE_CONFIDENCE_THRESHOLD = 0.5;

/**
 * Whether a reading should raise an alert. Mirrors integrated_monitor.py:
 * CRITICAL environmental risk -> HIGH alert, HIGH risk -> MODERATE alert.
 * Unlike the Python bridge it also acts on the node's own on-device AI
 * detection (ThingSpeak fields 7/8), escalating when the environment agrees.
 */
export function decideAlert(
  reading: SensorReading,
  riskLevel: RiskLevel,
): AlertDecision | null {
  if (reading.fireDetected && reading.aiConfidence >= AI_FIRE_CONFIDENCE_THRESHOLD) {
    const environmentAgrees = riskLevel === "HIGH" || riskLevel === "CRITICAL";
    return { type: "FIRE", severity: environmentAgrees ? "CRITICAL" : "HIGH" };
  }

  if (riskLevel === "CRITICAL") {
    return { type: "ENVIRONMENTAL_RISK", severity: "HIGH" };
  }

  if (riskLevel === "HIGH") {
    return { type: "ENVIRONMENTAL_RISK", severity: "MODERATE" };
  }

  return null;
}

/** Alerts that still need someone's attention. */
export const OPEN_STATUSES = ["ACTIVE", "ACKNOWLEDGED"];
