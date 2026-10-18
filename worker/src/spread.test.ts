import assert from "node:assert/strict";
import { test } from "node:test";

import { compass, estimateSpread, lengthToBreadth } from "./spread.js";

test("fires run downwind", () => {
  // Wind from the west (270°) pushes the head fire east (90°).
  const s = estimateSpread("pine", 92, 20, 270);
  assert.equal(s.towardDeg, 90);
  assert.equal(compass(s.towardDeg), "E");
});

test("dry windy pine spreads far faster than damp calm pine", () => {
  const dry = estimateSpread("pine", 94, 30, 0);
  const damp = estimateSpread("pine", 60, 5, 0);
  assert.ok(dry.headRos > 10 * damp.headRos, `${dry.headRos} vs ${damp.headRos}`);
});

test("FBP C-3 head ROS matches the published equation", () => {
  // FFMC 90, wind 20 km/h: ISI = 11.74 by hand, so
  // ROS = 110 * (1 - e^(-0.0444 * 11.74))^3 = 7.37 m/min.
  const s = estimateSpread("pine", 90, 20, 0);
  assert.ok(Math.abs(s.headRos - 7.37) < 0.05, `${s.headRos} m/min`);
  assert.equal(s.headDistance1h, Math.round(s.headRos * 60));
});

test("grass outruns forest under the same weather; wetland barely moves", () => {
  const grass = estimateSpread("grassland", 92, 20, 0);
  const deciduous = estimateSpread("dry_deciduous", 92, 20, 0);
  const wetland = estimateSpread("wetland", 92, 20, 0);
  assert.ok(grass.headRos > deciduous.headRos);
  assert.ok(wetland.headDistance1h < 60);
});

test("wind stretches the ellipse; back spread never exceeds head", () => {
  assert.equal(lengthToBreadth("C-3", 0), 1);
  assert.ok(lengthToBreadth("C-3", 40) > 3);
  const s = estimateSpread("bamboo", 88, 25, 45);
  assert.ok(s.backRos <= s.headRos);
});

test("unknown terrain falls back to mixed forest", () => {
  assert.equal(estimateSpread("volcano", 90, 10, 0).fuelModel, "M-1");
});
