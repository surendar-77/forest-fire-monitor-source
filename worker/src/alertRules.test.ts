import assert from "node:assert/strict";
import { test } from "node:test";

import { blocksNewDetection } from "./alertRules.js";

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
