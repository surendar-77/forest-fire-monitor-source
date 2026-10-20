/**
 * Sensor data relayed over LoRa: the node puts all its data in each radio
 * packet, a receiver (gateway) forwards the raw packet to POST /lora/data,
 * and the backend uses it whenever the node's own Wi-Fi feed has gone quiet.
 *
 * Packet (comma-separated KEY:VALUE, -999 = missing):
 *   NODE:1,PKT:42,T1:28.1,H1:66.0,T2:27.9,H2:69.0,MQ1:770,MQ2:-1,AI:Normal,CF:0.980,
 *   RK:12,LV:LOW,UP:3600,WF:1,CAM:3,MQH:0[,AL:FIRE-HIGH]
 * Kept free of Workers APIs so it can be unit-tested.
 */

import type { AiClass, SensorReading } from "./thingspeak.js";

export interface LoraPacket {
  pkt: number | null;
  t1: number | null;
  h1: number | null;
  t2: number | null;
  h2: number | null;
  mq1: number | null;
  mq2: number | null;
  ai: string | null;
  conf: number | null;
  risk: number | null;
  level: string | null;
  uptime: number | null;
  wifiUp: boolean | null;
  cameraAgeSec: number | null;
  smokeFault: boolean | null;
  alert: { type: "FIRE" | "SMOKE" | "ENVIRONMENTAL_RISK"; severity: "MODERATE" | "HIGH" | "CRITICAL" } | null;
}

export interface LoraDataBody {
  gateway: string;
  key: string;
  node: string;
  rssi: number | null;
  snr: number | null;
  packet: LoraPacket;
}

const ID = /^[A-Za-z0-9_-]{1,40}$/;
const AI_CLASSES = new Set(["Fire", "Normal", "Smoke"]);
const LEVELS = new Set(["LOW", "MEDIUM", "MODERATE", "HIGH", "CRITICAL", "WARMUP"]);
const ALERT_TYPES = new Set(["FIRE", "SMOKE", "ENVIRONMENTAL_RISK"]);
const SEVERITIES = new Set(["MODERATE", "HIGH", "CRITICAL"]);

function value(fields: Map<string, string>, key: string, min: number, max: number): number | null {
  const raw = fields.get(key);
  if (raw == null || raw === "") return null;
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= -998 || n < min || n > max) return null;
  return n;
}

/** The fields of a raw packet, or an error message. */
export function parseLoraPacket(raw: unknown): LoraPacket | string {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > 255) return "Invalid packet.";
  const fields = new Map<string, string>();
  for (const part of raw.split(",")) {
    const at = part.indexOf(":");
    if (at > 0) fields.set(part.slice(0, at).trim().toUpperCase(), part.slice(at + 1).trim());
  }
  if (!fields.has("NODE")) return "Packet has no NODE field.";

  const ai = fields.get("AI") ?? null;
  const level = (fields.get("LV") ?? "").toUpperCase();
  const wifi = fields.get("WF");
  const mqh = fields.get("MQH");

  let alert: LoraPacket["alert"] = null;
  const al = (fields.get("AL") ?? "").toUpperCase();
  if (al) {
    const dash = al.lastIndexOf("-");
    const type = dash > 0 ? al.slice(0, dash) : al;
    const severity = dash > 0 ? al.slice(dash + 1) : "HIGH";
    if (ALERT_TYPES.has(type) && SEVERITIES.has(severity)) {
      alert = { type: type as NonNullable<LoraPacket["alert"]>["type"], severity: severity as NonNullable<LoraPacket["alert"]>["severity"] };
    }
  }

  const pkt = value(fields, "PKT", 0, 1e9);
  const uptime = value(fields, "UP", 0, 1e9);
  const camera = value(fields, "CAM", -1, 1e9);
  return {
    pkt: pkt == null ? null : Math.round(pkt),
    t1: value(fields, "T1", -50, 100),
    h1: value(fields, "H1", 0, 100),
    t2: value(fields, "T2", -50, 100),
    h2: value(fields, "H2", 0, 100),
    mq1: value(fields, "MQ1", 0, 4095),
    mq2: value(fields, "MQ2", 0, 4095),
    ai: ai && AI_CLASSES.has(ai) ? ai : null,
    conf: value(fields, "CF", 0, 1),
    risk: value(fields, "RK", 0, 100),
    level: LEVELS.has(level) ? level : null,
    uptime: uptime == null ? null : Math.round(uptime),
    wifiUp: wifi === "1" ? true : wifi === "0" ? false : null,
    cameraAgeSec: camera == null ? null : Math.round(camera),
    smokeFault: mqh === "1" ? true : mqh === "0" ? false : null,
    alert,
  };
}

function num(v: unknown, min: number, max: number): number | null {
  return typeof v === "number" && Number.isFinite(v) && v >= min && v <= max ? v : null;
}

/** The POST /lora/data body, or an error message for the 400 response. */
export function parseLoraData(body: unknown): LoraDataBody | string {
  if (typeof body !== "object" || body === null) return "Body must be a JSON object.";
  const b = body as Record<string, unknown>;
  if (typeof b.gateway !== "string" || !ID.test(b.gateway)) return "Invalid gateway.";
  if (typeof b.node !== "string" || !ID.test(b.node)) return "Invalid node.";
  if (typeof b.key !== "string" || b.key.length < 16 || b.key.length > 128) return "Invalid key.";
  const packet = parseLoraPacket(b.packet);
  if (typeof packet === "string") return packet;
  return { gateway: b.gateway, key: b.key, node: b.node, rssi: num(b.rssi, -160, 0), snr: num(b.snr, -30, 30), packet };
}

/** A packet as a reading for the shared processing path. */
export function sensorReading(p: LoraPacket, now: Date): SensorReading {
  const ai = p.ai === "Fire" || p.ai === "Normal" || p.ai === "Smoke" ? (p.ai as AiClass) : null;
  return {
    temperature: p.t1,
    humidity: p.h1,
    temperature2: p.t2,
    humidity2: p.h2,
    mq2_1: p.mq1 ?? 0,
    mq2_2: p.mq2 ?? 0,
    aiClass: ai,
    fireDetected: ai === "Fire",
    smokeDetected: ai === "Smoke",
    aiConfidence: p.conf ?? 0,
    timestamp: now,
    entryId: null,
    ageSeconds: 0,
    isStale: false,
  };
}

/** The node's own live feed counts as alive if it wrote this recently. */
export const DIRECT_FRESH_MS = 30_000;
/** Device and history updates from LoRa at most this often. */
export const LORA_DEVICE_WRITE_MS = 60_000;

/** Live values (RTDB live/{node}/values shape) from a packet. */
export function liveValues(p: LoraPacket): Record<string, number | string> {
  const v: Record<string, number | string> = {};
  const put = (k: string, x: number | string | null) => {
    if (x != null) v[k] = x;
  };
  put("t1", p.t1);
  put("h1", p.h1);
  put("t2", p.t2);
  put("h2", p.h2);
  put("mq1", p.mq1);
  put("mq2", p.mq2);
  put("risk", p.risk);
  put("level", p.level);
  put("ai", p.ai);
  put("conf", p.conf);
  put("up", p.uptime);
  v.via = "lora";
  return v;
}

/** Fire alerts relayed by LoRa follow the same confidence rule as /alert. */
export function alertAllowed(p: LoraPacket, fireThreshold: number): boolean {
  if (!p.alert) return false;
  if (p.alert.type === "FIRE") return (p.conf ?? 0) >= fireThreshold;
  return true;
}
