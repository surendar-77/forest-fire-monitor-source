/**
 * Validation for alerts a node sends straight to the Worker
 * (POST /alert), so a fire reaches phones in seconds instead of waiting for
 * the next ThingSpeak poll. Kept free of Workers APIs so it can be unit-tested.
 */

export const DEVICE_ALERT_TYPES = ["FIRE", "SMOKE", "ENVIRONMENTAL_RISK"] as const;
export const SEVERITIES = ["LOW", "MODERATE", "HIGH", "CRITICAL"] as const;

export interface DeviceAlert {
  node: string;
  key: string;
  type: (typeof DEVICE_ALERT_TYPES)[number];
  severity: (typeof SEVERITIES)[number];
  temperature: number | null;
  humidity: number | null;
  mq2_1: number | null;
  mq2_2: number | null;
  aiClass: string | null;
  aiConfidence: number | null;
  riskScore: number | null;
}

const NODE_ID = /^[A-Za-z0-9_-]{1,40}$/;

function optionalNumber(value: unknown, min: number, max: number): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value < min || value > max ? null : value;
}

/** Returns the parsed alert, or an error message for the 400 response. */
export function parseDeviceAlert(body: unknown): DeviceAlert | string {
  if (typeof body !== "object" || body === null) return "Body must be a JSON object.";
  const b = body as Record<string, unknown>;

  if (typeof b.node !== "string" || !NODE_ID.test(b.node)) return "Invalid node.";
  if (typeof b.key !== "string" || b.key.length < 16 || b.key.length > 128) return "Invalid key.";
  if (!DEVICE_ALERT_TYPES.includes(b.type as DeviceAlert["type"])) return "Invalid type.";
  if (!SEVERITIES.includes(b.severity as DeviceAlert["severity"])) return "Invalid severity.";

  return {
    node: b.node,
    key: b.key,
    type: b.type as DeviceAlert["type"],
    severity: b.severity as DeviceAlert["severity"],
    temperature: optionalNumber(b.temperature, -50, 100),
    humidity: optionalNumber(b.humidity, 0, 100),
    mq2_1: optionalNumber(b.mq2_1, 0, 4095),
    mq2_2: optionalNumber(b.mq2_2, 0, 4095),
    aiClass: typeof b.aiClass === "string" ? b.aiClass.slice(0, 10) : null,
    aiConfidence: optionalNumber(b.aiConfidence, 0, 1),
    riskScore: optionalNumber(b.riskScore, 0, 100),
  };
}

/** Compares secrets without leaking how many leading characters matched. */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
