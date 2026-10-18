/**
 * Canadian Fire Weather Index components for the fire-danger model: FFMC
 * (Fine Fuel Moisture Code) and ISI (Initial Spread Index), Van Wagner
 * (1987). A line-for-line port of ml/fwi.py, which the model was trained
 * with, so training and runtime features are computed identically.
 */

export const FFMC_START = 85;

/** Next day's FFMC from noon temperature (°C), RH (%), wind (km/h), 24 h rain (mm). */
export function ffmc(temp: number, rh: number, wind: number, rain: number, ffmcPrev: number): number {
  rh = Math.min(Math.max(rh, 0), 100);
  let mo = (147.2 * (101 - ffmcPrev)) / (59.5 + ffmcPrev);

  if (rain > 0.5) {
    const rf = rain - 0.5;
    const wetting = 42.5 * rf * Math.exp(-100 / (251 - mo)) * (1 - Math.exp(-6.93 / rf));
    mo = mo > 150 ? mo + wetting + 0.0015 * (mo - 150) ** 2 * Math.sqrt(rf) : mo + wetting;
    mo = Math.min(mo, 250);
  }

  const ed =
    0.942 * rh ** 0.679 +
    11 * Math.exp((rh - 100) / 10) +
    0.18 * (21.1 - temp) * (1 - Math.exp(-0.115 * rh));

  let m: number;
  if (mo > ed) {
    const ko = 0.424 * (1 - (rh / 100) ** 1.7) + 0.0694 * Math.sqrt(wind) * (1 - (rh / 100) ** 8);
    const kd = ko * 0.581 * Math.exp(0.0365 * temp);
    m = ed + (mo - ed) * 10 ** -kd;
  } else {
    const ew =
      0.618 * rh ** 0.753 +
      10 * Math.exp((rh - 100) / 10) +
      0.18 * (21.1 - temp) * (1 - Math.exp(-0.115 * rh));
    if (mo < ew) {
      const k1 =
        0.424 * (1 - ((100 - rh) / 100) ** 1.7) +
        0.0694 * Math.sqrt(wind) * (1 - ((100 - rh) / 100) ** 8);
      const kw = k1 * 0.581 * Math.exp(0.0365 * temp);
      m = ew - (ew - mo) * 10 ** -kw;
    } else {
      m = mo;
    }
  }

  const value = (59.5 * (250 - m)) / (147.2 + m);
  return Math.min(Math.max(value, 0), 101);
}

export function isi(ffmcValue: number, wind: number): number {
  const fm = (147.2 * (101 - ffmcValue)) / (59.5 + ffmcValue);
  const fWind = Math.exp(0.05039 * wind);
  const fFuel = 91.9 * Math.exp(-0.1386 * fm) * (1 + fm ** 5.31 / 4.93e7);
  return 0.208 * fWind * fFuel;
}

export interface NoonWeather {
  temp: number;
  rh: number;
  wind: number;
  rain24h: number;
}

/** FFMC after consecutive days of noon weather, from the standard start value. */
export function ffmcAfter(days: NoonWeather[], start = FFMC_START): number {
  let value = start;
  for (const d of days) value = ffmc(d.temp, d.rh, d.wind, d.rain24h, value);
  return value;
}
