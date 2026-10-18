/**
 * Per-node smoke/heat anomaly detection (stage 2 of the detection model).
 *
 * Each node learns its own normal behaviour per sensor: a robust centre
 * (median) and spread (median absolute deviation, scaled to a standard
 * deviation), updated hourly from that node's readings. A reading is scored
 * by how many spreads it sits on the fire side of normal: more smoke,
 * hotter, drier. This replaces fixed thresholds, which can't fit sensors
 * whose clean-air level varies (MQ-2 raw ADC differs widely between units).
 *
 * Unsupervised: no fire examples needed. Stage 3 trains a classifier on
 * recorded test sessions on top of these features.
 */

/** The node's six sensors: two MQ-2 smoke, two DHT22 temperature/humidity. */
export type Sensor = "mq1" | "mq2" | "temp1" | "temp2" | "hum1" | "hum2";

export interface SensorStats {
  median: number;
  spread: number;
}

export interface Baseline {
  sensors: Partial<Record<Sensor, SensorStats>>;
  /** Readings that went into the baseline so far. */
  samples: number;
}

export type Reading = Record<Sensor, number | null>;

export type AnomalyLevel = "LEARNING" | "NORMAL" | "ELEVATED" | "SUSPICIOUS" | "LIKELY";

export interface AnomalyResult {
  /** 0-100 for display; 100 = far outside this node's normal range. */
  score: number;
  level: AnomalyLevel;
  /** One-sided deviations in spreads (only the fire direction counts). */
  z: Partial<Record<Sensor, number>>;
  /** Sensor furthest from normal, for explaining alerts. */
  driver: Sensor | null;
}

/** Readings needed before scoring is trusted (one hour at 1 per minute). */
export const MIN_SAMPLES = 60;

/**
 * Smallest spread allowed per sensor, so a very steady sensor doesn't turn
 * tiny wobbles into huge deviations. Roughly the sensor's own noise.
 */
const SPREAD_FLOOR: Record<Sensor, number> = {
  mq1: 40,
  mq2: 40,
  temp1: 0.8,
  temp2: 0.8,
  hum1: 3,
  hum2: 3,
};

/** Which way is "toward fire" for each sensor. */
const DIRECTION: Record<Sensor, 1 | -1> = {
  mq1: 1,
  mq2: 1,
  temp1: 1,
  temp2: 1,
  hum1: -1,
  hum2: -1,
};

export const SENSORS: Sensor[] = ["mq1", "mq2", "temp1", "temp2", "hum1", "hum2"];

/** How fast the baseline follows new hours (0.1 = ~10 hours memory). */
const LEARNING_RATE = 0.1;

export function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/** Median and MAD-based spread (1.4826 * MAD estimates a standard deviation). */
export function robustStats(values: number[]): SensorStats | null {
  if (values.length === 0) return null;
  const m = median(values);
  const mad = median(values.map((v) => Math.abs(v - m)));
  return { median: m, spread: 1.4826 * mad };
}

/** Stats for an hour of readings, per sensor. */
export function hourStats(readings: Reading[]): Partial<Record<Sensor, SensorStats>> {
  const stats: Partial<Record<Sensor, SensorStats>> = {};
  for (const sensor of SENSORS) {
    const values = readings
      .map((r) => r[sensor])
      .filter((v): v is number => typeof v === "number" && Number.isFinite(v));
    const s = robustStats(values);
    if (s) stats[sensor] = s;
  }
  return stats;
}

/** Blends an hour's stats into the baseline (the first hour sets it). */
export function updateBaseline(
  old: Baseline | null,
  hour: Partial<Record<Sensor, SensorStats>>,
  hourSamples: number,
): Baseline {
  const sensors: Partial<Record<Sensor, SensorStats>> = { ...(old?.sensors ?? {}) };

  for (const sensor of SENSORS) {
    const h = hour[sensor];
    if (!h) continue;
    const prev = sensors[sensor];
    sensors[sensor] = prev
      ? {
          median: prev.median + LEARNING_RATE * (h.median - prev.median),
          spread: prev.spread + LEARNING_RATE * (h.spread - prev.spread),
        }
      : { ...h };
  }

  return { sensors, samples: (old?.samples ?? 0) + hourSamples };
}

function levelFor(z: number): AnomalyLevel {
  if (z >= 6) return "LIKELY";
  if (z >= 4) return "SUSPICIOUS";
  if (z >= 2.5) return "ELEVATED";
  return "NORMAL";
}

export function scoreReading(reading: Reading, baseline: Baseline | null): AnomalyResult {
  if (!baseline || baseline.samples < MIN_SAMPLES) {
    return { score: 0, level: "LEARNING", z: {}, driver: null };
  }

  const z: Partial<Record<Sensor, number>> = {};
  let worst = 0;
  let driver: Sensor | null = null;

  for (const sensor of SENSORS) {
    const value = reading[sensor];
    const stats = baseline.sensors[sensor];
    if (value == null || !stats) continue;

    const spread = Math.max(stats.spread, SPREAD_FLOOR[sensor]);
    const deviation = (DIRECTION[sensor] * (value - stats.median)) / spread;
    const oneSided = Math.max(0, deviation);
    z[sensor] = Math.round(oneSided * 100) / 100;

    if (oneSided > worst) {
      worst = oneSided;
      driver = sensor;
    }
  }

  // Smoke with heat or dryness together is more telling than one sensor
  // alone: add a smaller share of the second-largest deviation.
  const sorted = Object.values(z).sort((a, b) => b - a);
  const combined = worst + 0.5 * (sorted[1] ?? 0);

  return {
    score: Math.min(100, Math.round((combined / 8) * 100)),
    level: levelFor(combined),
    z,
    driver: worst > 0 ? driver : null,
  };
}

/** An hour is clean enough to learn from if it held no likely anomalies. */
export function isLearnableHour(scores: number[]): boolean {
  if (scores.length === 0) return true;
  const likely = scores.filter((s) => s >= 75).length;
  return likely / scores.length < 0.1;
}
