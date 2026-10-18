/**
 * Satellite fire detections near nodes from NASA FIRMS (VIIRS, 375 m), the
 * same source India's Forest Survey uses for its Forest Fire Alert System.
 * An independent check on the ground sensors, and coverage between nodes.
 *
 * Needs a free MAP_KEY (https://firms.modaps.eosdis.nasa.gov/api/map_key/),
 * stored as the Worker secret FIRMS_MAP_KEY. Data arrives within about
 * 3 hours of each satellite pass.
 */

import { distanceKm } from "./fcm.js";

export interface Hotspot {
  latitude: number;
  longitude: number;
  /** "2026-10-19 07:42" UTC */
  acquired: string;
  satellite: string;
  /** VIIRS confidence: low / nominal / high */
  confidence: "low" | "nominal" | "high";
  /** Fire radiative power, MW */
  frp: number | null;
  distanceKm: number;
}

const SOURCES = ["VIIRS_NOAA20_NRT", "VIIRS_NOAA21_NRT"];

/** Degrees of latitude/longitude spanning `km` around a point. */
function bbox(lat: number, lng: number, km: number): string {
  const dLat = km / 111;
  const dLng = km / (111 * Math.max(Math.cos((lat * Math.PI) / 180), 0.1));
  const r = (v: number) => v.toFixed(4);
  return [r(lng - dLng), r(lat - dLat), r(lng + dLng), r(lat + dLat)].join(",");
}

const CONFIDENCE: Record<string, Hotspot["confidence"]> = { l: "low", n: "nominal", h: "high" };

/** Parses a FIRMS area CSV and keeps detections within `radiusKm` of the node. */
export function parseFirmsCsv(csv: string, lat: number, lng: number, radiusKm: number): Hotspot[] {
  const lines = csv.trim().split(/\r?\n/);
  if (lines.length < 2 || !lines[0].includes("latitude")) return [];
  const header = lines[0].split(",");
  const col = (name: string) => header.indexOf(name);
  const iLat = col("latitude");
  const iLng = col("longitude");
  const iDate = col("acq_date");
  const iTime = col("acq_time");
  const iSat = col("satellite");
  const iConf = col("confidence");
  const iFrp = col("frp");

  return lines.slice(1).flatMap((line): Hotspot[] => {
    const f = line.split(",");
    const hLat = Number(f[iLat]);
    const hLng = Number(f[iLng]);
    if (!Number.isFinite(hLat) || !Number.isFinite(hLng)) return [];
    const d = distanceKm(lat, lng, hLat, hLng);
    if (d > radiusKm) return [];

    const time = (f[iTime] ?? "").padStart(4, "0");
    const frpText = (f[iFrp] ?? "").trim();
    const frp = frpText === "" ? NaN : Number(frpText);
    return [
      {
        latitude: hLat,
        longitude: hLng,
        acquired: `${f[iDate]} ${time.slice(0, 2)}:${time.slice(2)}`,
        satellite: f[iSat] ?? "",
        confidence: CONFIDENCE[(f[iConf] ?? "").trim().toLowerCase()] ?? "nominal",
        frp: Number.isFinite(frp) ? frp : null,
        distanceKm: Math.round(d * 10) / 10,
      },
    ];
  });
}

/** Detections from the last 24 h within `radiusKm`, nearest first. */
export async function fetchHotspots(
  mapKey: string,
  lat: number,
  lng: number,
  radiusKm: number,
): Promise<Hotspot[]> {
  const area = bbox(lat, lng, radiusKm);
  const results = await Promise.all(
    SOURCES.map(async (source) => {
      const url = `https://firms.modaps.eosdis.nasa.gov/api/area/csv/${mapKey}/${source}/${area}/1`;
      const response = await fetch(url, { signal: AbortSignal.timeout(15_000) });
      if (!response.ok) throw new Error(`FIRMS ${source} returned HTTP ${response.status}`);
      return parseFirmsCsv(await response.text(), lat, lng, radiusKm);
    }),
  );

  // The two satellites can see the same fire; drop near-duplicates (<400 m).
  const unique: Hotspot[] = [];
  for (const h of results.flat().sort((a, b) => a.distanceKm - b.distanceKm)) {
    if (!unique.some((u) => distanceKm(u.latitude, u.longitude, h.latitude, h.longitude) < 0.4)) {
      unique.push(h);
    }
  }
  return unique;
}
