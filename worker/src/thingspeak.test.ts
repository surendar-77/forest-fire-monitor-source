import assert from "node:assert/strict";
import { test } from "node:test";

import { decideAlert } from "./alertRules.js";
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
  assert.equal(reading.fireDetected, false);
  assert.equal(reading.aiConfidence, 0.87);
  assert.equal(reading.entryId, 941);
  assert.equal(reading.ageSeconds, 30);
  assert.equal(reading.isStale, false);
});

test("old entries are stale", () => {
  const reading = parseFeed({ ...feed, created_at: "2026-10-18T11:55:00Z" }, now, 120);
  assert.equal(reading.isStale, true);
});

test("rejects missing or out-of-range primary readings", () => {
  assert.throws(() => parseFeed({ ...feed, field1: "" }, now, 120), /missing/);
  assert.throws(() => parseFeed({ ...feed, field2: "140" }, now, 120), /humidity/);
  assert.throws(() => parseFeed({ ...feed, field1: "99" }, now, 120), /temperature/);
  assert.throws(
    () => parseFeed({ ...feed, created_at: "2026-10-18T12:05:00Z" }, now, 120),
    /future/,
  );
});

test("on-device AI fire detection raises a FIRE alert", () => {
  const reading = parseFeed({ ...feed, field7: "1", field8: "0.9" }, now, 120);

  assert.deepEqual(decideAlert(reading, "LOW"), { type: "FIRE", severity: "HIGH" });
  assert.deepEqual(decideAlert(reading, "HIGH"), { type: "FIRE", severity: "CRITICAL" });
});

test("low-confidence AI detection falls back to environmental risk", () => {
  const reading = parseFeed({ ...feed, field7: "1", field8: "30" }, now, 120);

  assert.equal(decideAlert(reading, "LOW"), null);
  assert.deepEqual(decideAlert(reading, "CRITICAL"), {
    type: "ENVIRONMENTAL_RISK",
    severity: "HIGH",
  });
  assert.deepEqual(decideAlert(reading, "HIGH"), {
    type: "ENVIRONMENTAL_RISK",
    severity: "MODERATE",
  });
});
