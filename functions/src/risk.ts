/**
 * Environmental fire-risk model, ported from `calculate_risk` in the Python
 * bridge (forest_fire_integration_final/thingspeak_to_firebase.py) so both
 * produce identical levels for the same readings.
 *
 * Each sensor contributes 0-2 points; the total is normalised to a 12-point
 * scale when some secondary sensors are missing. The app shows risk out of
 * 100, so `score` is the 12-point total scaled to 0-100.
 */

export type RiskLevel = "LOW" | "MODERATE" | "HIGH" | "CRITICAL";

export interface RiskThresholds {
  tempWarn: number;
  tempHigh: number;
  humidityWarn: number;
  humidityHigh: number;
  mq2Warn: number;
  mq2High: number;
}

export const DEFAULT_THRESHOLDS: RiskThresholds = {
  tempWarn: 35,
  tempHigh: 45,
  humidityWarn: 30,
  humidityHigh: 20,
  mq2Warn: 400,
  mq2High: 800,
};

export interface RiskInput {
  temperature: number | null;
  humidity: number | null;
  mq2_1: number | null;
  mq2_2?: number | null;
  temperature2?: number | null;
  humidity2?: number | null;
}

export interface RiskResult {
  /** 0-12, same as the Python bridge's risk score. */
  points: number;
  /** 0-100, what the app displays. */
  score: number;
  level: RiskLevel;
}

function tempPoints(value: number | null | undefined, t: RiskThresholds): number {
  if (value == null) return 0;
  return value >= t.tempHigh ? 2 : value >= t.tempWarn ? 1 : 0;
}

function humidityPoints(value: number | null | undefined, t: RiskThresholds): number {
  if (value == null) return 0;
  return value <= t.humidityHigh ? 2 : value <= t.humidityWarn ? 1 : 0;
}

function mq2Points(value: number | null | undefined, t: RiskThresholds): number {
  if (value == null) return 0;
  return value >= t.mq2High ? 2 : value >= t.mq2Warn ? 1 : 0;
}

/** Python's round() rounds halves to even; match it exactly. */
function roundHalfEven(value: number): number {
  const floor = Math.floor(value);
  const diff = value - floor;
  if (Math.abs(diff - 0.5) < 1e-9) {
    return floor % 2 === 0 ? floor : floor + 1;
  }
  return Math.round(value);
}

export function levelForPoints(points: number): RiskLevel {
  if (points <= 2) return "LOW";
  if (points <= 5) return "MODERATE";
  if (points <= 8) return "HIGH";
  return "CRITICAL";
}

export function calculateRisk(
  input: RiskInput,
  thresholds: RiskThresholds = DEFAULT_THRESHOLDS,
): RiskResult {
  let score =
    tempPoints(input.temperature, thresholds) +
    humidityPoints(input.humidity, thresholds) +
    mq2Points(input.mq2_1, thresholds);
  let maxPoints = 6;

  if (input.temperature2 != null) {
    score += tempPoints(input.temperature2, thresholds);
    maxPoints += 2;
  }
  if (input.humidity2 != null) {
    score += humidityPoints(input.humidity2, thresholds);
    maxPoints += 2;
  }
  if (input.mq2_2 != null) {
    score += mq2Points(input.mq2_2, thresholds);
    maxPoints += 2;
  }

  const points = maxPoints < 12 ? roundHalfEven((score / maxPoints) * 12) : score;

  return {
    points,
    score: Math.round((points / 12) * 100),
    level: levelForPoints(points),
  };
}
