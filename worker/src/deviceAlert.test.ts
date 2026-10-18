import assert from "node:assert/strict";
import { test } from "node:test";

import { parseDeviceAlert, safeEqual } from "./deviceAlert.js";

const valid = {
  node: "NODE-01",
  key: "k".repeat(32),
  type: "FIRE",
  severity: "CRITICAL",
  temperature: 44.2,
  humidity: 18,
  mq2_1: 910,
  mq2_2: 880,
  aiClass: "Fire",
  aiConfidence: 0.93,
  riskScore: 92,
};

test("accepts a well-formed device alert", () => {
  const alert = parseDeviceAlert(valid);
  assert.equal(typeof alert, "object");
  assert.equal((alert as { severity: string }).severity, "CRITICAL");
});

test("rejects bad node, key, type and severity", () => {
  assert.equal(typeof parseDeviceAlert({ ...valid, node: "../x" }), "string");
  assert.equal(typeof parseDeviceAlert({ ...valid, key: "short" }), "string");
  assert.equal(typeof parseDeviceAlert({ ...valid, type: "NODE_OFFLINE" }), "string");
  assert.equal(typeof parseDeviceAlert({ ...valid, severity: "EXTREME" }), "string");
  assert.equal(typeof parseDeviceAlert(null), "string");
});

test("out-of-range readings are dropped, not trusted", () => {
  const alert = parseDeviceAlert({ ...valid, temperature: 999, humidity: "wet" });
  assert.equal(typeof alert, "object");
  assert.equal((alert as { temperature: unknown }).temperature, null);
  assert.equal((alert as { humidity: unknown }).humidity, null);
});

test("safeEqual compares exactly", () => {
  assert.equal(safeEqual("abc123", "abc123"), true);
  assert.equal(safeEqual("abc123", "abc124"), false);
  assert.equal(safeEqual("abc", "abcd"), false);
});
