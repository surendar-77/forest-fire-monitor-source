import assert from "node:assert/strict";
import { test } from "node:test";

import { terrainDanger } from "./fireDanger.js";
import { adjustProbability, combineRisk, riskLevel, terrainFor } from "./terrain.js";

test("terrain factors scale the odds and stay within 0-1", () => {
  assert.equal(adjustProbability(0.5, 1), 0.5);
  assert.ok(Math.abs(adjustProbability(0.5, 1.8) - 0.643) < 0.001);
  assert.ok(Math.abs(adjustProbability(0.5, 0.4) - 0.286) < 0.001);
  assert.equal(adjustProbability(0, 1.8), 0);
  assert.equal(adjustProbability(1, 0.4), 1);
});

test("unknown or missing terrain falls back to mixed forest", () => {
  assert.equal(terrainFor(undefined).id, "mixed");
  assert.equal(terrainFor("volcano").id, "mixed");
  assert.equal(terrainFor("bamboo").label, "Bamboo (moongil) forest");
});

test("three risk levels", () => {
  assert.equal(riskLevel(0.2), "LOW");
  assert.equal(riskLevel(0.5), "MEDIUM");
  assert.equal(riskLevel(0.8), "HIGH");
});

test("the same weather is riskier in a pine forest than in a desert", () => {
  const chance = 0.15; // raw model chance of a detected fire today
  const base = { anomalyScore: 0, cameraFire: false, cameraSmoke: false };
  const pine = combineRisk({ ...base, dangerProbability: terrainDanger(chance, 1.8), terrain: terrainFor("pine") });
  const desert = combineRisk({ ...base, dangerProbability: terrainDanger(chance, 0.4), terrain: terrainFor("desert") });

  assert.equal(pine.level, "HIGH");
  assert.equal(desert.level, "LOW");
  assert.equal(pine.driver, "weather");
});

test("sensor anomalies drive risk when weather is calm", () => {
  const risk = combineRisk({
    anomalyScore: 60,
    dangerProbability: 0.05,
    terrain: terrainFor("bamboo"),
    cameraFire: false,
    cameraSmoke: false,
  });
  assert.equal(risk.driver, "sensors");
  assert.equal(risk.level, "HIGH");
});

test("camera fire is always High; camera smoke is at least High", () => {
  const calm = { anomalyScore: 0, dangerProbability: 0.01, terrain: terrainFor("wetland") };
  assert.deepEqual(
    [combineRisk({ ...calm, cameraFire: true, cameraSmoke: false }).level, combineRisk({ ...calm, cameraFire: true, cameraSmoke: false }).score],
    ["HIGH", 100],
  );
  assert.equal(combineRisk({ ...calm, cameraFire: false, cameraSmoke: true }).level, "HIGH");
});

test("no data at all is Low", () => {
  const risk = combineRisk({
    anomalyScore: 0,
    dangerProbability: null,
    terrain: terrainFor("mixed"),
    cameraFire: false,
    cameraSmoke: false,
  });
  assert.deepEqual([risk.level, risk.driver], ["LOW", "none"]);
});
