import assert from "node:assert/strict";
import { test } from "node:test";

import { calculateRisk, levelForPoints } from "./risk.js";

// Expected values were produced by the Python bridge's calculate_risk()
// with the same inputs, so a change in either implementation shows up here.

test("all sensors calm is LOW", () => {
  const result = calculateRisk({
    temperature: 28,
    humidity: 60,
    mq2_1: 150,
    mq2_2: 140,
    temperature2: 27,
    humidity2: 62,
  });
  assert.deepEqual(result, { points: 0, score: 0, level: "LOW" });
});

test("all sensors at high thresholds is CRITICAL", () => {
  const result = calculateRisk({
    temperature: 46,
    humidity: 15,
    mq2_1: 900,
    mq2_2: 850,
    temperature2: 47,
    humidity2: 18,
  });
  assert.deepEqual(result, { points: 12, score: 100, level: "CRITICAL" });
});

test("primary sensors only are normalised to 12 points", () => {
  // 1 + 1 + 1 = 3 of 6 -> 6 of 12
  const result = calculateRisk({ temperature: 36, humidity: 25, mq2_1: 500 });
  assert.equal(result.points, 6);
  assert.equal(result.level, "HIGH");
  assert.equal(result.score, 50);
});

test("normalisation rounds halves to even like Python", () => {
  // 1 of 8 points -> 1.5 of 12 -> Python round() gives 2
  const result = calculateRisk({
    temperature: 36,
    humidity: 60,
    mq2_1: 100,
    mq2_2: 100,
  });
  assert.equal(result.points, 2);
  assert.equal(result.level, "LOW");
});

test("missing primary readings count as zero", () => {
  const result = calculateRisk({ temperature: null, humidity: null, mq2_1: 900 });
  assert.equal(result.points, 4);
  assert.equal(result.level, "MODERATE");
});

test("level boundaries match the Python bridge", () => {
  assert.equal(levelForPoints(2), "LOW");
  assert.equal(levelForPoints(3), "MODERATE");
  assert.equal(levelForPoints(5), "MODERATE");
  assert.equal(levelForPoints(6), "HIGH");
  assert.equal(levelForPoints(8), "HIGH");
  assert.equal(levelForPoints(9), "CRITICAL");
});
