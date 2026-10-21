import assert from "node:assert/strict";
import { test } from "node:test";

import { loraLink, loraQuality, parseLoraReport } from "./lora.js";

const valid = {
  gateway: "GW-01",
  key: "k".repeat(32),
  node: "NODE-01",
  packets: 22,
  lost: 2,
  rssi: -97.4,
  rssiMin: -104,
  snr: 8.25,
  lastPacketAgoSec: 3,
  windowSec: 60,
};

test("a valid report parses", () => {
  const r = parseLoraReport(valid);
  assert.ok(typeof r !== "string");
  assert.equal(r.packets, 22);
  assert.equal(r.rssi, -97.4);
});

test("bad reports are rejected", () => {
  assert.equal(parseLoraReport(null), "Body must be a JSON object.");
  assert.equal(parseLoraReport({ ...valid, gateway: "bad id!" }), "Invalid gateway.");
  assert.equal(parseLoraReport({ ...valid, key: "short" }), "Invalid key.");
  assert.equal(parseLoraReport({ ...valid, packets: -1 }), "Invalid packet counts.");
});

test("out-of-range signal values are dropped, and ignored with no packets", () => {
  const r = parseLoraReport({ ...valid, rssi: 20, snr: 99 });
  assert.ok(typeof r !== "string");
  assert.equal(r.rssi, null);
  assert.equal(r.snr, null);

  const silent = parseLoraReport({ ...valid, packets: 0, lost: 24 });
  assert.ok(typeof silent !== "string");
  assert.equal(silent.rssi, null);
});

test("signal grades", () => {
  assert.deepEqual(loraQuality(-70, 9), { quality: "Excellent", bars: 4 });
  assert.deepEqual(loraQuality(-102, 13), { quality: "Excellent", bars: 4 }); // SF10 at the desk
  assert.deepEqual(loraQuality(-110, 7), { quality: "Good", bars: 3 });
  assert.deepEqual(loraQuality(-120, 2), { quality: "Fair", bars: 2 });
  assert.deepEqual(loraQuality(-118, -10), { quality: "Weak", bars: 1 }); // noisy link drops a step
  assert.deepEqual(loraQuality(-128, 0), { quality: "Weak", bars: 1 });
  assert.deepEqual(loraQuality(null, null), { quality: "No signal", bars: 0 });
});

test("stored link has loss percent and last packet time", () => {
  const r = parseLoraReport(valid);
  assert.ok(typeof r !== "string");
  const now = new Date("2026-10-19T10:00:00Z");
  const link = loraLink(r, now);
  assert.equal(link.lossPercent, 8);
  assert.equal(link.rssi, -97);
  assert.equal(link.snr, 8.3);
  assert.equal(link.quality, "Excellent"); // -97 dBm has plenty of margin at SF10
  assert.deepEqual(link.lastPacketAt, new Date("2026-10-19T09:59:57Z"));
  assert.ok(!("key" in link));
});
