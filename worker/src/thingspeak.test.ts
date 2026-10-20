import assert from "node:assert/strict";
import { test } from "node:test";

import { decideAlert } from "./alertRules.js";
import type { AnomalyResult } from "./anomaly.js";
import { parseFeed } from "./thingspeak.js";

const now = new Date("2026-10-18T12:00:00Z");

const feed = {
  created_at: "2026-10-18T11:59:30Z",
  entry_id: 941,
  field1: "31.5",
  field2: "48",
  field3: "30.9",
  field4: "",
  field5: "420",
  field6: null,
  field7: "0",
  field8: "87",
};

test("parses fields, blanks and percent confidence", () => {
  const reading = parseFeed(feed, now, 120);

  assert.equal(reading.temperature, 31.5);
  assert.equal(reading.humidity, 48);
  assert.equal(reading.temperature2, 30.9);
  assert.equal(reading.humidity2, null);
  assert.equal(reading.mq2_1, 420);
  assert.equal(reading.mq2_2, 0);
  // field7 "0" is the Fire class
  assert.equal(reading.aiClass, "Fire");
  assert.equal(reading.fireDetected, true);
  assert.equal(reading.aiConfidence, 0.87);
  assert.equal(reading.entryId, 941);
  assert.equal(reading.ageSeconds, 30);
  assert.equal(reading.isStale, false);
});

test("old entries are stale", () => {
  const reading = parseFeed({ ...feed, created_at: "2026-10-18T11:55:00Z" }, now, 120);
  assert.equal(reading.isStale, true);
});

test("a silent DHT22 still lets smoke and AI data through", () => {
  const reading = parseFeed({ ...feed, field1: "", field2: "" }, now, 120);
  assert.equal(reading.temperature, null);
  assert.equal(reading.humidity, null);
  assert.equal(reading.mq2_1, 420);
});

test("rejects empty or out-of-range readings", () => {
  assert.throws(
    () => parseFeed({ ...feed, field1: "", field2: "", field5: "" }, now, 120),
    /no temperature, humidity or smoke/,
  );
  assert.throws(() => parseFeed({ ...feed, field2: "140" }, now, 120), /humidity/);
  assert.throws(() => parseFeed({ ...feed, field1: "99" }, now, 120), /temperature/);
  assert.throws(
    () => parseFeed({ ...feed, created_at: "2026-10-18T12:05:00Z" }, now, 120),
    /future/,
  );
});

const normal: AnomalyResult = { score: 5, level: "NORMAL", z: {}, driver: null };
const likely: AnomalyResult = { score: 90, level: "LIKELY", z: { mq1: 7.2 }, driver: "mq1" };
const suspicious: AnomalyResult = { score: 55, level: "SUSPICIOUS", z: { mq1: 4.4 }, driver: "mq1" };

test("a confident Normal frame with normal sensors raises nothing", () => {
  const reading = parseFeed({ ...feed, field7: "1", field8: "0.95" }, now, 120);

  assert.equal(reading.aiClass, "Normal");
  assert.equal(reading.fireDetected, false);
  assert.equal(decideAlert(reading, normal, "LOW"), null);
});

test("camera Smoke class raises a SMOKE alert, stronger when sensors or danger agree", () => {
  const reading = parseFeed({ ...feed, field7: "2", field8: "81" }, now, 120);

  assert.deepEqual(decideAlert(reading, normal, "LOW"), { type: "SMOKE", severity: "MODERATE" });
  assert.deepEqual(decideAlert(reading, suspicious, "LOW"), { type: "SMOKE", severity: "HIGH" });
  assert.deepEqual(decideAlert(reading, normal, "VERY HIGH"), { type: "SMOKE", severity: "HIGH" });
});

test("camera Fire class raises a FIRE alert", () => {
  const reading = parseFeed({ ...feed, field7: "0", field8: "0.9" }, now, 120);

  assert.deepEqual(decideAlert(reading, normal, null), { type: "FIRE", severity: "HIGH" });
  assert.deepEqual(decideAlert(reading, likely, null), { type: "FIRE", severity: "CRITICAL" });
});

test("a likely sensor anomaly alerts on its own; danger raises severity", () => {
  const reading = parseFeed({ ...feed, field7: "1", field8: "0.9" }, now, 120);

  assert.deepEqual(decideAlert(reading, likely, "LOW"), { type: "SENSOR_ANOMALY", severity: "HIGH" });
  assert.deepEqual(decideAlert(reading, likely, "HIGH"), { type: "SENSOR_ANOMALY", severity: "CRITICAL" });
  assert.equal(decideAlert(reading, suspicious, "HIGH"), null);
});

test("camera Fire below 75% confidence raises no alert", () => {
  const reading = parseFeed({ ...feed, field7: "0", field8: "0.74" }, now, 120);
  assert.equal(decideAlert(reading, normal, "VERY HIGH"), null);

  const sure = parseFeed({ ...feed, field7: "0", field8: "0.75" }, now, 120);
  assert.deepEqual(decideAlert(sure, normal, null), { type: "FIRE", severity: "HIGH" });
});

test("camera Smoke still alerts from 50% confidence", () => {
  const reading = parseFeed({ ...feed, field7: "2", field8: "0.6" }, now, 120);
  assert.deepEqual(decideAlert(reading, normal, "LOW"), { type: "SMOKE", severity: "MODERATE" });
});

test("low-confidence camera detection doesn't alert by itself", () => {
  const reading = parseFeed({ ...feed, field7: "0", field8: "30" }, now, 120);
  assert.equal(decideAlert(reading, normal, "VERY HIGH"), null);
});
