import assert from "node:assert/strict";
import { test } from "node:test";

import { distanceKm } from "./fcm.js";
import { alertMessage, parseFireServices, stationsFor } from "./fireServices.js";

const config = parseFireServices({
  radiusKm: 25,
  stations: [
    { name: "Station A (near)", telegramChatId: "-1001", latitude: 12.98, longitude: 77.6 },
    { name: "Station B (far)", telegramChatId: -1002, latitude: 13.5, longitude: 78.5 },
    { name: "No location", telegramChatId: "-1003" },
    { name: "Broken entry" },
  ],
});

test("parses stations and skips incomplete entries", () => {
  assert.equal(config.stations.length, 3);
  assert.equal(config.stations[1].telegramChatId, "-1002");
});

test("distance is accurate enough for station selection", () => {
  // Bengaluru to Chennai is roughly 290 km.
  const d = distanceKm(12.9716, 77.5946, 13.0827, 80.2707);
  assert.ok(d > 280 && d < 300, `${d}`);
});

test("only stations within range are told", () => {
  const picked = stationsFor(config, 12.97, 77.59);
  assert.deepEqual(picked.map((s) => s.name), ["Station A (near)"]);
});

test("if no station is in range, all are told; same without a node location", () => {
  assert.equal(stationsFor(config, 20, 70).length, 3);
  assert.equal(stationsFor(config, null, null).length, 3);
});

test("message includes the essentials and a map link", () => {
  const text = alertMessage(
    { type: "FIRE", severity: "CRITICAL", deviceId: "NODE-01", temperature: 44.5, latitude: 12.97, longitude: 77.59 },
    "Ridge camp",
  );
  assert.match(text, /CRITICAL · FIRE DETECTED/);
  assert.match(text, /Ridge camp \(NODE-01\)/);
  assert.match(text, /maps\.google\.com\/\?q=12\.970000,77\.590000/);
});
