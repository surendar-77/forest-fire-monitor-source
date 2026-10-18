import assert from "node:assert/strict";
import { test } from "node:test";

import { aqiCategory } from "./airQuality.js";
import { parseFirmsCsv } from "./firms.js";

// Shape of a FIRMS VIIRS area CSV.
const CSV = `latitude,longitude,bright_ti4,scan,track,acq_date,acq_time,satellite,instrument,confidence,version,bright_ti5,frp,daynight
12.9800,77.6000,340.1,0.4,0.4,2026-10-19,742,N20,VIIRS,h,2.0NRT,295.2,12.4,D
13.4000,77.6000,330.0,0.4,0.4,2026-10-19,742,N20,VIIRS,n,2.0NRT,290.0,4.1,D
12.9900,77.6100,310.5,0.4,0.4,2026-10-19,2015,N21,VIIRS,l,2.0NRT,288.0,,N`;

test("parses FIRMS rows and keeps only those within range", () => {
  const hotspots = parseFirmsCsv(CSV, 12.97, 77.59, 10);
  assert.equal(hotspots.length, 2); // the 13.40 row is ~48 km away
  assert.equal(hotspots[0].confidence, "high");
  assert.equal(hotspots[0].acquired, "2026-10-19 07:42");
  assert.equal(hotspots[1].frp, null);
  assert.equal(hotspots[1].acquired, "2026-10-19 20:15");
  assert.ok(hotspots[0].distanceKm < 2);
});

test("an empty or error response yields no hotspots", () => {
  assert.deepEqual(parseFirmsCsv("", 0, 0, 10), []);
  assert.deepEqual(parseFirmsCsv("Invalid MAP_KEY.", 0, 0, 10), []);
});

test("AQI categories follow the US EPA bands", () => {
  assert.equal(aqiCategory(42), "Good");
  assert.equal(aqiCategory(130), "Unhealthy for sensitive groups");
  assert.equal(aqiCategory(320), "Hazardous");
  assert.equal(aqiCategory(null), "Unknown");
});
