import assert from "node:assert/strict";
import test from "node:test";

import { alertMessageFor } from "./alertMessages.js";

test("fire message says what, how sure, readings and what to do", () => {
  const m = alertMessageFor("FIRE", {
    nodeName: "Hill top",
    severity: "CRITICAL",
    aiConfidence: 0.92,
    temperature: 41.2,
    humidity: 18,
    smoke: 1450,
    dangerLevel: "HIGH",
  });
  assert.match(m, /camera at Hill top sees flames \(92% sure\)/);
  assert.match(m, /41\.2 °C, 18% humidity, smoke level 1450/);
  assert.match(m, /smoke and heat sensors agree/);
  assert.match(m, /could spread fast/);
  assert.match(m, /call the fire service/);
});

test("smoke, anomaly, satellite, offline and risk messages", () => {
  assert.match(alertMessageFor("SMOKE", { nodeName: "N", severity: "MODERATE", aiConfidence: 0.6 }), /sees smoke \(60% sure\)/);
  const anomaly = alertMessageFor("SENSOR_ANOMALY", { nodeName: "N", severity: "HIGH", anomalyDriver: "mq1", anomalyZ: 7 });
  assert.match(anomaly, /far above normal/);
  assert.match(anomaly, /smoke sensor 1/);
  assert.match(
    alertMessageFor("SATELLITE_HOTSPOT", { nodeName: "N", severity: "HIGH", distanceKm: 3.24, satellite: "VIIRS", satelliteConfidence: "high" }),
    /fire 3\.2 km from N \(VIIRS, high confidence\)/,
  );
  assert.match(
    alertMessageFor("NODE_OFFLINE", { nodeName: "N", severity: "HIGH", lastSeen: new Date("2026-10-20T08:00:00Z") }),
    /stopped sending data since 1:30 pm/i,
  );
  assert.match(alertMessageFor("ENVIRONMENTAL_RISK", { nodeName: "N", severity: "HIGH" }), /favour fire/);
});

test("zero readings are left out", () => {
  const m = alertMessageFor("FIRE", { nodeName: "N", severity: "HIGH", temperature: 0, humidity: 0 });
  assert.doesNotMatch(m, /Readings/);
});
