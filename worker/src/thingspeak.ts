/**
 * Parsing of a ThingSpeak `feeds/last.json` entry, ported from
 * `get_sensor_data` in the Python bridge. Field layout (per channel):
 *   1 Temperature 1 (°C)   2 Humidity 1 (%)
 *   3 Temperature 2 (°C)   4 Humidity 2 (%)
 *   5 MQ-2 sensor 1        6 MQ-2 sensor 2
 *   7 AI class: 0 Fire, 1 Normal, 2 Smoke (as ForestFire_S3.ino sends it)
 *   8 AI confidence of that class (0-1 or 0-100)
 */

export type AiClass = "Fire" | "Normal" | "Smoke";

const AI_CLASSES: AiClass[] = ["Fire", "Normal", "Smoke"];

export interface ThingSpeakFeed {
  created_at?: string;
  entry_id?: number;
  [field: string]: unknown;
}

export interface SensorReading {
  /** Null when the DHT22 gave no reading; smoke and AI data still count. */
  temperature: number | null;
  humidity: number | null;
  temperature2: number | null;
  humidity2: number | null;
  mq2_1: number;
  mq2_2: number;
  /** The camera model's latest prediction, or null before the first one. */
  aiClass: AiClass | null;
  fireDetected: boolean;
  smokeDetected: boolean;
  /** Confidence of aiClass, 0-1 */
  aiConfidence: number;
  timestamp: Date;
  entryId: number | null;
  ageSeconds: number;
  isStale: boolean;
}

function field(feed: ThingSpeakFeed, n: number): number | null {
  const raw = feed[`field${n}`];
  if (raw == null || String(raw).trim() === "") return null;
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

export function parseFeed(
  feed: ThingSpeakFeed,
  now: Date,
  maxAgeSeconds: number,
): SensorReading {
  const temperature = field(feed, 1);
  const humidity = field(feed, 2);

  if (temperature == null && humidity == null && field(feed, 5) == null) {
    throw new Error("Entry has no temperature, humidity or smoke reading");
  }
  if (!feed.created_at) {
    throw new Error("ThingSpeak timestamp is missing");
  }

  const timestamp = new Date(feed.created_at);
  if (Number.isNaN(timestamp.getTime())) {
    throw new Error(`Invalid ThingSpeak timestamp: ${feed.created_at}`);
  }

  const ageSeconds = (now.getTime() - timestamp.getTime()) / 1000;
  if (ageSeconds < -30) {
    throw new Error("ThingSpeak timestamp is unexpectedly in the future");
  }
  if (humidity != null && (humidity < 0 || humidity > 100)) {
    throw new Error(`Invalid primary humidity reading: ${humidity}`);
  }
  if (temperature != null && (temperature < -40 || temperature > 85)) {
    throw new Error(`Invalid primary temperature reading: ${temperature}`);
  }

  let confidence = field(feed, 8) ?? 0;
  if (confidence > 1 && confidence <= 100) confidence /= 100;

  const classIndex = field(feed, 7);
  const aiClass =
    classIndex != null && Number.isInteger(classIndex) ? AI_CLASSES[classIndex] ?? null : null;

  return {
    temperature,
    humidity,
    temperature2: field(feed, 3),
    humidity2: field(feed, 4),
    mq2_1: field(feed, 5) ?? 0,
    mq2_2: field(feed, 6) ?? 0,
    aiClass,
    fireDetected: aiClass === "Fire",
    smokeDetected: aiClass === "Smoke",
    aiConfidence: confidence,
    timestamp,
    entryId: typeof feed.entry_id === "number" ? feed.entry_id : null,
    ageSeconds: Math.max(0, ageSeconds),
    isStale: ageSeconds > maxAgeSeconds,
  };
}

export async function fetchLastFeed(
  channelId: string,
  readApiKey?: string,
): Promise<ThingSpeakFeed> {
  const url = new URL(`https://api.thingspeak.com/channels/${channelId}/feeds/last.json`);
  if (readApiKey) url.searchParams.set("api_key", readApiKey);

  const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!response.ok) {
    throw new Error(`ThingSpeak channel ${channelId} returned HTTP ${response.status}`);
  }

  const body = (await response.json()) as ThingSpeakFeed | -1;
  if (body === -1 || body == null || typeof body !== "object") {
    throw new Error(`ThingSpeak channel ${channelId} has no data or is private`);
  }
  return body;
}
