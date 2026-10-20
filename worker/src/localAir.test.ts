import assert from "node:assert/strict";
import test from "node:test";

import type { AnomalyResult } from "./anomaly.js";
import { localAir } from "./localAir.js";

const result = (z: AnomalyResult["z"]): AnomalyResult => ({ score: 0, level: "NORMAL", z, driver: null });

test("clean, slight, smoke, heavy smoke and gas", () => {
  assert.equal(localAir(result({ mq1: 0.5 }), "Normal", 0.95, true).status, "CLEAN");
  assert.equal(localAir(result({ mq1: 2.5 }), "Normal", 0.95, true).status, "SLIGHT");
  assert.equal(localAir(result({ mq1: 5 }), "Smoke", 0.8, true).status, "SMOKE");
  assert.equal(localAir(result({ mq1: 5, temp1: 3 }), "Normal", 0.9, true).status, "SMOKE");
  assert.equal(localAir(result({ mq1: 9 }), "Fire", 0.9, true).status, "HEAVY_SMOKE");
  const gas = localAir(result({ mq1: 6 }), "Normal", 0.95, true);
  assert.equal(gas.status, "GAS");
  assert.match(gas.detail, /LPG/);
});

test("camera smoke alone, a low-confidence camera, learning and no reading", () => {
  assert.equal(localAir(result({ mq1: 0 }), "Smoke", 0.7, true).label, "Smoke seen by camera");
  assert.equal(localAir(result({ mq1: 6 }), "Smoke", 0.3, true).status, "GAS");
  assert.equal(localAir({ score: 0, level: "LEARNING", z: {}, driver: null }, null, 0, true).status, "LEARNING");
  assert.equal(localAir(result({}), null, 0, false).status, "UNKNOWN");
});
