/**
 * Parsing of a ThingSpeak `feeds/last.json` entry, ported from
 * `get_sensor_data` in the Python bridge. Field layout (per channel):
 *   1 Temperature 1 (°C)   2 Humidity 1 (%)
 *   3 Temperature 2 (°C)   4 Humidity 2 (%)
 *   5 MQ-2 sensor 1        6 MQ-2 sensor 2
 *   7 Fire detected (0/1)  8 AI confidence (0-1 or 0-100)
 */

export interface ThingSpeakFeed {
  created_at?: string;
  entry_id?: number;
  [field: string]: unknown;
}

export interface SensorReading {
  temperature: number;
  humidity: number;
  temperature2: number | null;
  humidity2: number | null;
  mq2_1: number;
  mq2_2: number;
  fireDetected: boolean;
  /** 0-1 */
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

  if (temperature == null || humidity == null) {
    throw new Error("Primary sensor (temperature/humidity) reading is missing");
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
  if (humidity < 0 || humidity > 100) {
    throw new Error(`Invalid primary humidity reading: ${humidity}`);
  }
  if (temperature < -40 || temperature > 85) {
    throw new Error(`Invalid primary temperature reading: ${temperature}`);
  }

  let confidence = field(feed, 8) ?? 0;
  if (confidence > 1 && confidence <= 100) confidence /= 100;

  return {
    temperature,
    humidity,
    temperature2: field(feed, 3),
    humidity2: field(feed, 4),
    mq2_1: field(feed, 5) ?? 0,
    mq2_2: field(feed, 6) ?? 0,
    fireDetected: (field(feed, 7) ?? 0) >= 1,
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
