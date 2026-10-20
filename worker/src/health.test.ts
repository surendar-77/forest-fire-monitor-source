import assert from "node:assert/strict";
import test from "node:test";

import { currentIssues, isHealthAlert, parseHealth, planHealth } from "./health.js";

const now = new Date("2026-10-20T08:00:00Z");
const report = (extra: Record<string, unknown>) =>
  parseHealth({ ts: now.getTime() - 20_000, up: 7200, camAge: 2, dht1: true, dht2: true, mq: "ok", rssi: -50, ...extra })!;

test("a healthy board has no issues", () => {
  assert.deepEqual(currentIssues(report({})), []);
  const plan = planHealth(report({}), now, null, null)!;
  assert.deepEqual(plan.raise, []);
  assert.ok(plan.clear.includes("CAMERA_OFFLINE"));
  assert.ok(!plan.clear.includes("POWER_PROBLEM"), "brownout alerts are resolved by people");
});

test("camera gone 10 min alerts at once; never-connected waits for 10 min uptime", () => {
  const plan = planHealth(report({ camAge: 700 }), now, null, null)!;
  assert.equal(plan.raise[0].type, "CAMERA_OFFLINE");
  assert.match(plan.raise[0].message, /12 min/);

  assert.deepEqual(currentIssues(report({ camAge: -1, up: 120 })), []);
  assert.equal(currentIssues(report({ camAge: -1, up: 900 }))[0].type, "CAMERA_OFFLINE");
});

test("a dead sensor must last 10 minutes before it alerts", () => {
  const first = planHealth(report({ dht2: false }), now, null, null)!;
  assert.deepEqual(first.raise, []);
  assert.equal(first.since.SENSOR_FAULT.getTime(), now.getTime());

  const later = new Date(now.getTime() + 11 * 60_000);
  const second = planHealth(
    parseHealth({ ts: later.getTime(), dht1: true, dht2: false, camAge: 1 })!,
    later,
    first.since,
    null,
  )!;
  assert.equal(second.raise[0].type, "SENSOR_FAULT");
  assert.match(second.raise[0].message, /sensor 2/);
});

test("a faulty smoke sensor counts; 'MQ2 not installed' does not", () => {
  assert.equal(currentIssues(report({ mq: "MQ1 faulty: jumping values (loose wire?)" }))[0].type, "SENSOR_FAULT");
  assert.deepEqual(currentIssues(report({ mq: "ok (MQ2 not installed)" })), []);
});

test("a brownout restart alerts once per restart", () => {
  const plan = planHealth(report({ boot: "brownout", boots: 7 }), now, null, null)!;
  assert.equal(plan.raise[0].type, "POWER_PROBLEM");
  assert.equal(plan.brownoutStart, 7);
  assert.deepEqual(planHealth(report({ boot: "brownout", boots: 7 }), now, null, 7)!.raise, []);
});

test("battery levels and a hot chip", () => {
  assert.equal(currentIssues(report({ bat: 15 }))[0].severity, "MODERATE");
  assert.equal(currentIssues(report({ bat: 8 }))[0].severity, "HIGH");
  assert.equal(currentIssues(report({ chipT: 85 }))[0].type, "BOARD_HOT");
  assert.equal(currentIssues(report({ rssi: -88 }))[0].type, "WEAK_WIFI");
});

test("an old report is not judged", () => {
  const old = parseHealth({ ts: now.getTime() - 10 * 60_000, camAge: 900 })!;
  assert.equal(planHealth(old, now, null, null), null);
  assert.equal(parseHealth(null), null);
  assert.ok(isHealthAlert("LOW_BATTERY"));
  assert.ok(!isHealthAlert("FIRE"));
});
