/**
 * Air quality at a node from the Open-Meteo Air Quality API (free, no key).
 * Smoke raises PM2.5 and carbon monoxide well before many fires are seen,
 * so it corroborates the node's own smoke sensors (cf. Watch Duty's AQI
 * layer).
 */

export interface AirQuality {
  pm25: number | null;
  pm10: number | null;
  usAqi: number | null;
  carbonMonoxide: number | null;
  category: string;
}

/** US EPA AQI categories. */
export function aqiCategory(aqi: number | null): string {
  if (aqi == null) return "Unknown";
  if (aqi <= 50) return "Good";
  if (aqi <= 100) return "Moderate";
  if (aqi <= 150) return "Unhealthy for sensitive groups";
  if (aqi <= 200) return "Unhealthy";
  if (aqi <= 300) return "Very unhealthy";
  return "Hazardous";
}

export async function fetchAirQuality(latitude: number, longitude: number): Promise<AirQuality> {
  const url = new URL("https://air-quality-api.open-meteo.com/v1/air-quality");
  url.searchParams.set("latitude", latitude.toFixed(4));
  url.searchParams.set("longitude", longitude.toFixed(4));
  url.searchParams.set("current", "pm2_5,pm10,us_aqi,carbon_monoxide");

  const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new Error(`Open-Meteo air quality returned HTTP ${response.status}`);
  const body = (await response.json()) as { current?: Record<string, number | null> };
  const c = body.current ?? {};
  const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? Math.round(v * 10) / 10 : null);

  const usAqi = num(c.us_aqi);
  return {
    pm25: num(c.pm2_5),
    pm10: num(c.pm10),
    usAqi,
    carbonMonoxide: num(c.carbon_monoxide),
    category: aqiCategory(usAqi),
  };
}
