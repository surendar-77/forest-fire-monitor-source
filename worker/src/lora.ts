/**
 * LoRa link reports from a receiver (gateway) board: POST /lora once a
 * minute with the signal of the packets it heard from a node in that
 * minute. Signal strength can only be measured by the receiving radio, so
 * this is the only place the app can learn it. Kept free of Workers APIs so
 * it can be unit-tested.
 */

export interface LoraReport {
  gateway: string;
  key: string;
  node: string;
  /** Packets heard in the window and packets missing from the sequence. */
  packets: number;
  lost: number;
  /** Average and weakest RSSI (dBm) and average SNR (dB) over the window. */
  rssi: number | null;
  rssiMin: number | null;
  snr: number | null;
  /** Seconds since the last packet, when one was ever heard. */
  lastPacketAgoSec: number | null;
  windowSec: number;
}

const ID = /^[A-Za-z0-9_-]{1,40}$/;

function num(value: unknown, min: number, max: number): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value < min || value > max ? null : value;
}

function count(value: unknown): number | null {
  const n = num(value, 0, 100_000);
  return n == null ? null : Math.round(n);
}

/** Returns the parsed report, or an error message for the 400 response. */
export function parseLoraReport(body: unknown): LoraReport | string {
  if (typeof body !== "object" || body === null) return "Body must be a JSON object.";
  const b = body as Record<string, unknown>;

  if (typeof b.gateway !== "string" || !ID.test(b.gateway)) return "Invalid gateway.";
  if (typeof b.node !== "string" || !ID.test(b.node)) return "Invalid node.";
  if (typeof b.key !== "string" || b.key.length < 16 || b.key.length > 128) return "Invalid key.";

  const packets = count(b.packets);
  const lost = count(b.lost);
  if (packets == null || lost == null) return "Invalid packet counts.";

  return {
    gateway: b.gateway,
    key: b.key,
    node: b.node,
    packets,
    lost,
    rssi: packets > 0 ? num(b.rssi, -160, 0) : null,
    rssiMin: packets > 0 ? num(b.rssiMin, -160, 0) : null,
    snr: packets > 0 ? num(b.snr, -30, 30) : null,
    lastPacketAgoSec: count(b.lastPacketAgoSec),
    windowSec: count(b.windowSec) ?? 60,
  };
}

export type LoraQuality = "Excellent" | "Good" | "Fair" | "Weak" | "No signal";

/**
 * Signal quality for SX127x (RA-02) at SF7/125 kHz, whose sensitivity is
 * about -123 dBm: RSSI sets the grade, a poor SNR (noise) lowers it one step.
 */
export function loraQuality(rssi: number | null, snr: number | null): { quality: LoraQuality; bars: number } {
  if (rssi == null) return { quality: "No signal", bars: 0 };
  let bars = rssi >= -80 ? 4 : rssi >= -95 ? 3 : rssi >= -110 ? 2 : 1;
  if (snr != null && snr < -5 && bars > 1) bars--;
  const quality: LoraQuality[] = ["No signal", "Weak", "Fair", "Good", "Excellent"];
  return { quality: quality[bars], bars };
}

/** What is stored on devices/{node}.lora for the app. */
export function loraLink(report: LoraReport, now: Date): Record<string, unknown> {
  const expected = report.packets + report.lost;
  const { quality, bars } = loraQuality(report.rssi, report.snr);
  return {
    gateway: report.gateway,
    rssi: report.rssi == null ? null : Math.round(report.rssi),
    rssiMin: report.rssiMin == null ? null : Math.round(report.rssiMin),
    snr: report.snr == null ? null : Math.round(report.snr * 10) / 10,
    packets: report.packets,
    lost: report.lost,
    lossPercent: expected === 0 ? null : Math.round((report.lost / expected) * 100),
    quality,
    bars,
    windowSec: report.windowSec,
    lastPacketAt:
      report.lastPacketAgoSec == null ? null : new Date(now.getTime() - report.lastPacketAgoSec * 1000),
    updatedAt: now,
  };
}
