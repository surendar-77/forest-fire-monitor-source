import assert from "node:assert/strict";
import { test } from "node:test";

import {
  dangerIndex,
  dangerLevel,
  fireChance,
  fireDangerModel,
  fireDangerProbability,
  rawProbability,
} from "./fireDanger.js";
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
    const p = rawProbability(input);
    assert.ok(Math.abs(p - probability) < 1e-5, `${input}: ${p} vs ${probability}`);
  }
});

test("model features are the ones the Worker computes", () => {
  assert.deepEqual(fireDangerModel.features, ["Temperature", "RH", "Wind", "Rain", "FFMC", "ISI", "MonthSin", "MonthCos"]);
});

test("a dry April afternoon in central India is far more dangerous than a monsoon day", () => {
  const april = fireDangerProbability({ temp: 39, rh: 15, wind: 15, rain24h: 0, ffmc: 94, isi: isi(94, 15), month: 4 });
  const monsoon = fireDangerProbability({ temp: 28, rh: 88, wind: 10, rain24h: 20, ffmc: 40, isi: isi(40, 10), month: 8 });
  assert.ok(april >= 0.5, `april ${april}`);
  assert.ok(monsoon < 0.1, `monsoon ${monsoon}`);
});

test("the same weather is more dangerous in the fire season", () => {
  const day = { temp: 33, rh: 30, wind: 12, rain24h: 0, ffmc: 90, isi: isi(90, 12) };
  assert.ok(fireChance({ ...day, month: 3 }) > fireChance({ ...day, month: 10 }));
});

test("danger index maps the raw chance through the level breakpoints", () => {
  const l = fireDangerModel.levels!;
  assert.equal(dangerIndex(0), 0);
  assert.ok(Math.abs(dangerIndex(l.medium) - 1 / 3) < 1e-9);
  assert.ok(Math.abs(dangerIndex(l.high) - 2 / 3) < 1e-9);
  assert.equal(dangerIndex(l.max), 1);
  assert.equal(dangerIndex(0.9), 1);
  assert.ok(dangerIndex(l.medium / 2) < dangerIndex(l.medium));
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
