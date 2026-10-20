import assert from "node:assert/strict";
import { test } from "node:test";

import { blocksNewDetection, foldRepeatDetection, outageEnded } from "./alertRules.js";

test("only recent open alerts silence a new detection", () => {
  const now = new Date("2026-10-19T09:00:00Z");
  const ago = (min: number) => new Date(now.getTime() - min * 60_000);
  assert.equal(blocksNewDetection({ status: "ACTIVE", detectedAt: ago(3) }, now), true);
  assert.equal(blocksNewDetection({ status: "ACTIVE", detectedAt: ago(15) }, now), false);
  // The real bug: a fire alert nobody resolved for 9 days must not block a new fire.
  assert.equal(blocksNewDetection({ status: "ACTIVE", timestamp: "2026-10-10T12:07:00Z" }, now), false);
  assert.equal(blocksNewDetection({ status: "ACKNOWLEDGED", detectedAt: ago(40), acknowledgedAt: ago(20) }, now), true);
  assert.equal(blocksNewDetection({ status: "ACKNOWLEDGED", detectedAt: ago(90), acknowledgedAt: ago(45) }, now), false);
  assert.equal(blocksNewDetection({ status: "ACTIVE" }, now), false); // no time: treat as old
  assert.equal(blocksNewDetection({ status: "RESOLVED", detectedAt: ago(1) }, now), false);
});

test("fire seen for 2 minutes without a break is confirmed once", () => {
  const t0 = new Date("2026-10-19T10:00:00Z");
  const at = (s: number) => new Date(t0.getTime() + s * 1000);
  let alert: Record<string, unknown> = { type: "FIRE", status: "ACTIVE", detectedAt: t0 };

  let u = foldRepeatDetection(alert, at(60));
  assert.equal(u.confirmNow, false);
  alert = { ...alert, ...u };

  u = foldRepeatDetection(alert, at(120));
  assert.equal(u.confirmNow, true); // 0 s, 60 s, 120 s: two minutes of fire
  assert.equal(u.detections, 3);
  alert = { ...alert, ...u, confirmedAt: at(120) };

  assert.equal(foldRepeatDetection(alert, at(180)).confirmNow, false); // only once
});

test("a gap restarts the 2-minute streak; smoke is never confirmed", () => {
  const t0 = new Date("2026-10-19T10:00:00Z");
  const at = (s: number) => new Date(t0.getTime() + s * 1000);
  // Seen at 0 s, then nothing until 5 min: the streak starts again.
  const u = foldRepeatDetection({ type: "FIRE", detectedAt: t0 }, at(300));
  assert.equal(u.confirmNow, false);
  assert.deepEqual(u.streakStartedAt, at(300));
  assert.equal(
    foldRepeatDetection({ type: "SMOKE", detectedAt: t0, lastDetectedAt: at(60) }, at(120)).confirmNow,
    false,
  );
});

test("an offline alert is over once the node reported after it", () => {
  const raised = new Date("2026-10-18T14:08:00Z");
  const alert = { type: "NODE_OFFLINE", status: "ACTIVE", detectedAt: raised };
  // The real case: raised yesterday, node reported again today, then went quiet.
  assert.equal(outageEnded(alert, new Date("2026-10-19T13:38:00Z")), true);
  // Still the same outage: nothing heard since it was raised.
  assert.equal(outageEnded(alert, new Date("2026-10-18T13:55:00Z")), false);
  assert.equal(outageEnded(alert, null), false);
});
