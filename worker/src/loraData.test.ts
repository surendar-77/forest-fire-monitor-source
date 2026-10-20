import assert from "node:assert/strict";
import test from "node:test";

import { alertAllowed, liveValues, parseLoraData, parseLoraPacket, sensorReading } from "./loraData.js";

const raw =
  "NODE:1,PKT:42,T1:28.1,H1:66.0,T2:-999.0,H2:69.0,MQ1:770,MQ2:-1,AI:Normal,CF:0.980,RK:12,LV:LOW,UP:3600,WF:1,CAM:3,MQH:0";

test("a full packet parses; -999 and -1 mean missing", () => {
  const p = parseLoraPacket(raw);
  assert.equal(typeof p, "object");
  if (typeof p === "string") return;
  assert.equal(p.pkt, 42);
  assert.equal(p.t1, 28.1);
  assert.equal(p.t2, null);
  assert.equal(p.mq2, null);
  assert.equal(p.ai, "Normal");
  assert.equal(p.conf, 0.98);
  assert.equal(p.risk, 12);
  assert.equal(p.level, "LOW");
  assert.equal(p.uptime, 3600);
  assert.equal(p.wifiUp, true);
  assert.equal(p.cameraAgeSec, 3);
  assert.equal(p.smokeFault, false);
  assert.equal(p.alert, null);
});

test("the old short packet still parses", () => {
  const p = parseLoraPacket("NODE:1,PKT:40,T1:26.8,H1:74.8,T2:26.8,H2:76.9,MQ1:917,MQ2:0,AI:Normal,CF:0.949");
  assert.equal(typeof p, "object");
  if (typeof p === "string") return;
  assert.equal(p.mq2, 0);
  assert.equal(p.risk, null);
  assert.equal(p.wifiUp, null);
});

test("alerts in a packet, and the 75% fire rule", () => {
  const fire = parseLoraPacket("NODE:1,PKT:5,AI:Fire,CF:0.910,AL:FIRE-CRITICAL");
  assert.ok(typeof fire === "object");
  if (typeof fire === "string") return;
  assert.deepEqual(fire.alert, { type: "FIRE", severity: "CRITICAL" });
  assert.equal(alertAllowed(fire, 0.75), true);

  const weak = parseLoraPacket("NODE:1,PKT:6,AI:Fire,CF:0.600,AL:FIRE-HIGH");
  assert.ok(typeof weak === "object" && !alertAllowed(weak, 0.75));

  const smoke = parseLoraPacket("NODE:1,PKT:7,AI:Smoke,CF:0.550,AL:SMOKE-MODERATE");
  assert.ok(typeof smoke === "object" && alertAllowed(smoke, 0.75));

  const bogus = parseLoraPacket("NODE:1,PKT:8,AL:EXPLODE-HIGH");
  assert.ok(typeof bogus === "object" && bogus.alert === null);
});

test("bad packets and bodies are refused", () => {
  assert.equal(typeof parseLoraPacket(""), "string");
  assert.equal(typeof parseLoraPacket("PKT:1,T1:20"), "string");
  assert.equal(typeof parseLoraPacket("x".repeat(300)), "string");
  assert.equal(typeof parseLoraData({ gateway: "GW-01", key: "short", node: "NODE-01", packet: raw }), "string");
  const ok = parseLoraData({ gateway: "GW-01", key: "0123456789abcdef0123", node: "NODE-01", packet: raw, rssi: -107, snr: 4 });
  assert.equal(typeof ok, "object");
});

test("live values carry only known readings and say they came by LoRa", () => {
  const p = parseLoraPacket(raw);
  assert.ok(typeof p === "object");
  if (typeof p === "string") return;
  const v = liveValues(p);
  assert.equal(v.t1, 28.1);
  assert.equal("t2" in v, false);
  assert.equal(v.via, "lora");
  assert.equal(v.ai, "Normal");
});

test("a packet becomes a reading for the shared path (risk, anomaly, alerts)", () => {
  const p = parseLoraPacket("NODE:1,PKT:9,T1:31.2,H1:40.0,T2:-999,H2:41.5,MQ1:1200,MQ2:-1,AI:Fire,CF:0.920");
  assert.ok(typeof p === "object");
  if (typeof p === "string") return;
  const r = sensorReading(p, new Date("2026-10-20T12:00:00Z"));
  assert.equal(r.temperature, 31.2);
  assert.equal(r.temperature2, null);
  assert.equal(r.mq2_1, 1200);
  assert.equal(r.mq2_2, 0);
  assert.equal(r.aiClass, "Fire");
  assert.equal(r.fireDetected, true);
  assert.equal(r.aiConfidence, 0.92);
  assert.equal(r.isStale, false);
});
