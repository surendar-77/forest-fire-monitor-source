import assert from "node:assert/strict";
import { test } from "node:test";

import {
  hourStats,
  isLearnableHour,
  robustStats,
  scoreReading,
  updateBaseline,
  type Baseline,
  type Reading,
} from "./anomaly.js";

// Clean air on the user's node: MQ-1 ~1100, MQ-2 ~1400 (noisy), 26 °C, 80 %.
function cleanHour(): Reading[] {
  return Array.from({ length: 60 }, (_, i) => ({
    mq1: 1100 + ((i * 7) % 41) - 20,
    mq2: 1400 + ((i * 13) % 201) - 100,
    temp1: 26.4 + ((i % 3) - 1) * 0.1,
    temp2: 26.4 + ((i % 3) - 1) * 0.1,
    hum1: 80 + ((i % 5) - 2) * 0.4,
    hum2: 82 + ((i % 5) - 2) * 0.4,
  }));
}

/** A reading with all six sensors; unspecified ones at clean-air values. */
function r(values: Partial<Reading>): Reading {
  return { mq1: 1100, mq2: 1400, temp1: 26.4, temp2: 26.4, hum1: 80, hum2: 82, ...values };
}

function learned(): Baseline {
  return updateBaseline(null, hourStats(cleanHour()), 60);
}

test("robust stats ignore a single spike", () => {
  const s = robustStats([10, 11, 9, 10, 12, 10, 500]);
  assert.equal(s?.median, 10);
  assert.ok((s?.spread ?? 99) < 3);
});

test("nothing is scored until an hour of readings is learned", () => {
  const s = scoreReading(r({ mq1: 4095, mq2: 4095, temp1: 60, hum1: 5 }), updateBaseline(null, {}, 10));
  assert.equal(s.level, "LEARNING");
});

test("clean air on a high-reading sensor is normal (no fixed thresholds)", () => {
  const s = scoreReading(r({ mq1: 1110, mq2: 1450, temp1: 26.5, hum1: 79.5 }), learned());
  assert.equal(s.level, "NORMAL");
  assert.ok(s.score < 30, `score ${s.score}`);
});

test("a smoke plume well above this node's normal is likely", () => {
  const s = scoreReading(r({ mq1: 2400, mq2: 2900 }), learned());
  assert.equal(s.level, "LIKELY");
  assert.equal(s.driver, "mq1");
});

test("heat with dryness and smoke together scores highest", () => {
  // A modest smoke rise, alone and then with heat and dryness.
  const smokeOnly = scoreReading(r({ mq1: 1220 }), learned());
  const all = scoreReading(r({ mq1: 1220, temp1: 29, hum1: 70 }), learned());
  assert.ok(all.score > smokeOnly.score, `${all.score} vs ${smokeOnly.score}`);
  assert.notEqual(all.level, "NORMAL");
});

test("only the fire direction counts: colder or wetter is not an anomaly", () => {
  const s = scoreReading(r({ temp1: 15, temp2: 15, hum1: 99, hum2: 99 }), learned());
  assert.equal(s.level, "NORMAL");
  assert.equal(s.z.temp1, 0);
  assert.equal(s.z.hum2, 0);
  assert.ok(s.score < 5, `score ${s.score}`);
});

test("all six sensors are scored; the second DHT22 can drive an alert", () => {
  const s = scoreReading(r({ temp2: 34, hum2: 50 }), learned());
  assert.deepEqual(Object.keys(s.z).sort(), ["hum1", "hum2", "mq1", "mq2", "temp1", "temp2"]);
  assert.ok(s.driver === "temp2" || s.driver === "hum2");
  assert.notEqual(s.level, "NORMAL");
});

test("baseline follows slow drift but not a single odd hour", () => {
  let b = learned();
  const shifted = cleanHour().map((r) => ({ ...r, mq1: (r.mq1 ?? 0) + 200 }));
  b = updateBaseline(b, hourStats(shifted), 60);
  const m = b.sensors.mq1?.median ?? 0;
  assert.ok(m > 1100 && m < 1150, `one hour moves the median ~10%: ${m}`);
});

test("hours dominated by anomalies are not learned from", () => {
  assert.equal(isLearnableHour(Array(60).fill(10)), true);
  assert.equal(isLearnableHour([...Array(50).fill(10), ...Array(10).fill(90)]), false);
});
