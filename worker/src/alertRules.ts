import type { RiskLevel } from "./risk.js";
import type { SensorReading } from "./thingspeak.js";

export interface AlertDecision {
  type: "FIRE" | "SMOKE" | "ENVIRONMENTAL_RISK";
  severity: RiskLevel;
}

export const AI_FIRE_CONFIDENCE_THRESHOLD = 0.5;

/**
 * Whether a reading should raise an alert. Mirrors integrated_monitor.py:
 * CRITICAL environmental risk -> HIGH alert, HIGH risk -> MODERATE alert.
 * Unlike the Python bridge it also acts on the node's camera AI (ThingSpeak
 * fields 7/8: Fire or Smoke class with enough confidence), escalating when
 * the environment agrees.
 */
export function decideAlert(
  reading: SensorReading,
  riskLevel: RiskLevel,
): AlertDecision | null {
  const confident = reading.aiConfidence >= AI_FIRE_CONFIDENCE_THRESHOLD;
  const environmentAgrees = riskLevel === "HIGH" || riskLevel === "CRITICAL";

  if (reading.fireDetected && confident) {
    return { type: "FIRE", severity: environmentAgrees ? "CRITICAL" : "HIGH" };
  }

  if (reading.smokeDetected && confident) {
    return { type: "SMOKE", severity: environmentAgrees ? "HIGH" : "MODERATE" };
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
