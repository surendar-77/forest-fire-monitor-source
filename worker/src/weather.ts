/**
 * Standard weather for the fire-danger model from Open-Meteo (free, no key):
 * 2 m temperature and humidity, 10 m wind and precipitation, hourly, for the
 * past 14 days. The Fire Weather Index is defined on such standard noon
 * observations, which a sensor under the canopy doesn't provide.
 */

import { type NoonWeather } from "./fwi.js";

export interface HourlyWeather {
  time: string[]; // local ISO times, "2026-10-18T12:00"
  temperature_2m: (number | null)[];
  relative_humidity_2m: (number | null)[];
  wind_speed_10m: (number | null)[];
  precipitation: (number | null)[];
}

export interface DangerInputs {
  /** Noon weather for each completed day, oldest first (FFMC spin-up). */
  pastNoons: NoonWeather[];
  /**
   * Today's noon weather: observed once noon has passed, otherwise the
   * forecast. Fire danger is a daily rating defined on noon weather, which
   * is also what the training data holds.
   */
  today: NoonWeather;
  todayNoon: string;
  forecast: boolean;
}

export interface WeatherResponse {
  hourly: HourlyWeather;
  /** Local time at the node, "YYYY-MM-DDTHH", for picking past hours. */
  nowLocal: string;
}

export async function fetchHourlyWeather(
  latitude: number,
  longitude: number,
): Promise<WeatherResponse> {
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", latitude.toFixed(4));
  url.searchParams.set("longitude", longitude.toFixed(4));
  url.searchParams.set(
    "hourly",
    "temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation",
  );
  url.searchParams.set("wind_speed_unit", "kmh");
  url.searchParams.set("past_days", "14");
  url.searchParams.set("forecast_days", "2"); // covers the next 24 h at any time of day
  url.searchParams.set("timezone", "auto");

  const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new Error(`Open-Meteo returned HTTP ${response.status}`);
  const body = (await response.json()) as { hourly?: HourlyWeather; utc_offset_seconds?: number };
  if (!body.hourly?.time?.length) throw new Error("Open-Meteo returned no hourly data");
  const offset = (body.utc_offset_seconds ?? 0) * 1000;
  return {
    hourly: body.hourly,
    nowLocal: new Date(Date.now() + offset).toISOString().slice(0, 13),
  };
}

function rainBefore(w: HourlyWeather, index: number): number {
  let total = 0;
  for (let i = Math.max(0, index - 23); i <= index; i++) total += w.precipitation[i] ?? 0;
  return total;
}

function at(w: HourlyWeather, i: number): NoonWeather | null {
  const temp = w.temperature_2m[i];
  const rh = w.relative_humidity_2m[i];
  const wind = w.wind_speed_10m[i];
  if (temp == null || rh == null || wind == null) return null;
  return { temp, rh, wind, rain24h: rainBefore(w, i) };
}

export interface HourWeather {
  time: string;
  weather: NoonWeather;
}

/** Forecast for the next `count` hours after now (for the danger timeline). */
export function upcomingHours(w: HourlyWeather, nowLocal: string, count = 24): HourWeather[] {
  const hours: HourWeather[] = [];
  for (let i = 0; i < w.time.length && hours.length < count; i++) {
    if (w.time[i].slice(0, 13) <= nowLocal) continue;
    const weather = at(w, i);
    if (weather) hours.push({ time: w.time[i], weather });
  }
  return hours;
}

/**
 * Splits hourly weather into completed days' noon values and today's noon.
 * `nowLocal` is the current local time as "YYYY-MM-DDTHH" (Open-Meteo's
 * timezone=auto).
 */
export function dangerInputs(w: HourlyWeather, nowLocal: string): DangerInputs | null {
  const today = nowLocal.slice(0, 10);
  const pastNoons: NoonWeather[] = [];
  let todayIndex = -1;

  for (let i = 0; i < w.time.length; i++) {
    const t = w.time[i];
    if (!t.endsWith("T12:00")) continue;

    const day = t.slice(0, 10);
    if (day < today) {
      const noon = at(w, i);
      if (noon) pastNoons.push(noon);
    } else if (day === today) {
      todayIndex = i;
    }
  }

  const todayNoon = todayIndex >= 0 ? at(w, todayIndex) : null;
  if (!todayNoon) return null;
  return {
    pastNoons,
    today: todayNoon,
    todayNoon: w.time[todayIndex],
    forecast: nowLocal < `${today}T12`,
  };
}
