import assert from "node:assert/strict";
import { test } from "node:test";

import { dangerLevel, fireDangerModel, fireDangerProbability } from "./fireDanger.js";
import { ffmc, isi } from "./fwi.js";
import { dangerInputs, type HourlyWeather } from "./weather.js";

// [temp, rh, wind, rain, ffmcPrev, ffmc, isi] from ml/fwi.py.
const FWI_CASES = [
  [30, 40, 15, 0, 85, 90.326252, 9.565854],
  [22, 85, 10, 12.5, 88, 42.354051, 0.088201],
  [38, 20, 25, 0, 92, 96.240677, 36.119231],
  [26, 60, 5, 0.4, 70, 82.07388, 1.850457],
  [15, 95, 20, 30, 60, 17.488879, 0.00013],
];

test("FFMC and ISI match the Python implementation the model was trained with", () => {
  for (const [t, rh, w, r, prev, expectedFfmc, expectedIsi] of FWI_CASES) {
    const f = ffmc(t, rh, w, r, prev);
    assert.ok(Math.abs(f - expectedFfmc) < 1e-4, `ffmc ${f} vs ${expectedFfmc}`);
    assert.ok(Math.abs(isi(f, w) - expectedIsi) < 1e-4, `isi vs ${expectedIsi}`);
  }
});

test("model probabilities match scikit-learn", () => {
  for (const { input, probability } of fireDangerModel.fixtures) {
    const p = fireDangerProbability(input);
    assert.ok(Math.abs(p - probability) < 1e-5, `${input}: ${p} vs ${probability}`);
  }
});

test("hot, dry, windy weather scores higher than cool, wet weather", () => {
  const dry = fireDangerProbability([38, 0, isi(94, 25)]);
  const wet = fireDangerProbability([24, 15, isi(40, 10)]);
  assert.ok(dry > 0.75, `dry ${dry}`);
  assert.ok(wet < 0.25, `wet ${wet}`);
});

test("danger levels", () => {
  assert.equal(dangerLevel(0.1), "LOW");
  assert.equal(dangerLevel(0.3), "MODERATE");
  assert.equal(dangerLevel(0.6), "HIGH");
  assert.equal(dangerLevel(0.9), "VERY HIGH");
});

test("weather is split into past noons and today's noon", () => {
  const time: string[] = [];
  for (const day of ["2026-10-16", "2026-10-17", "2026-10-18"]) {
    for (let h = 0; h < 24; h++) time.push(`${day}T${String(h).padStart(2, "0")}:00`);
  }
  const n = time.length;
  const w: HourlyWeather = {
    time,
    temperature_2m: time.map((_, i) => 20 + (i % 24)),
    relative_humidity_2m: Array(n).fill(50),
    wind_speed_10m: Array(n).fill(10),
    precipitation: time.map((t) => (t === "2026-10-17T06:00" ? 4 : 0)),
  };

  const afternoon = dangerInputs(w, "2026-10-18T15");
  assert.ok(afternoon);
  assert.equal(afternoon.pastNoons.length, 2); // 16th and 17th; today's noon isn't a past day
  assert.equal(afternoon.pastNoons[1].rain24h, 4); // rain at 06:00 falls in the 24 h before noon
  assert.equal(afternoon.todayNoon, "2026-10-18T12:00");
  assert.equal(afternoon.today.temp, 32); // noon, not the 15:00 reading
  assert.equal(afternoon.forecast, false);

  const morning = dangerInputs(w, "2026-10-18T08");
  assert.equal(morning?.forecast, true); // today's noon is still a forecast
});
