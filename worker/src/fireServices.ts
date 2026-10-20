/**
 * Notifies fire services about serious alerts through a Telegram bot
 * (free, instant, works on any phone with Telegram).
 *
 * Stations live in Firestore `config/fireServices`:
 *   { radiusKm: 25,
 *     stations: [{ name, telegramChatId, latitude?, longitude?, phone? }] }
 * Stations within radiusKm of the node are told; if none has a location (or
 * none is in range), every station is told, so an alert is never dropped.
 * The bot token is the Worker secret TELEGRAM_BOT_TOKEN.
 */

import { distanceKm } from "./fcm.js";
import type { Plain } from "./firestore.js";

export interface Station {
  name: string;
  telegramChatId: string;
  latitude?: number;
  longitude?: number;
  phone?: string;
}

export interface FireServicesConfig {
  radiusKm: number;
  stations: Station[];
}

export function parseFireServices(data: Record<string, Plain> | null | undefined): FireServicesConfig {
  const radiusKm = typeof data?.radiusKm === "number" ? data.radiusKm : 25;
  const raw = Array.isArray(data?.stations) ? data.stations : [];

  const stations = raw.flatMap((entry): Station[] => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry) || entry instanceof Date) return [];
    const s = entry as Record<string, Plain>;
    if (typeof s.name !== "string" || (typeof s.telegramChatId !== "string" && typeof s.telegramChatId !== "number")) {
      return [];
    }
    return [
      {
        name: s.name,
        telegramChatId: String(s.telegramChatId),
        latitude: typeof s.latitude === "number" ? s.latitude : undefined,
        longitude: typeof s.longitude === "number" ? s.longitude : undefined,
        phone: typeof s.phone === "string" ? s.phone : undefined,
      },
    ];
  });

  return { radiusKm, stations };
}

/** Stations to notify for an alert at (lat, lng). */
export function stationsFor(config: FireServicesConfig, lat: number | null, lng: number | null): Station[] {
  if (lat == null || lng == null || (lat === 0 && lng === 0)) return config.stations;

  const inRange = config.stations.filter(
    (s) =>
      s.latitude != null &&
      s.longitude != null &&
      distanceKm(lat, lng, s.latitude, s.longitude) <= config.radiusKm,
  );
  return inRange.length > 0 ? inRange : config.stations;
}

export function alertMessage(alert: Record<string, Plain>, nodeName: string): string {
  const kind =
    alert.type === "FIRE"
      ? "FIRE DETECTED (camera AI)"
      : alert.type === "SMOKE"
        ? "SMOKE DETECTED (camera AI)"
        : alert.type === "SENSOR_ANOMALY"
          ? "Smoke/heat anomaly on sensors"
          : alert.type === "NODE_OFFLINE"
            ? "Sensor went offline"
          : typeof alert.message === "string"
            ? "Sensor problem"
          : alert.type === "SATELLITE_HOTSPOT"
            ? "Satellite fire detection (NASA VIIRS)"
            : String(alert.type ?? "Fire alert");

  const lines = [
    `${typeof alert.message === "string" ? "🔧" : "🔥"} ${alert.severity ?? "HIGH"} · ${kind}`,
    `Node: ${nodeName} (${alert.deviceId ?? "?"})`,
  ];
  if (typeof alert.message === "string") lines.push(alert.message);
  if (typeof alert.temperature === "number" && alert.temperature !== 0) {
    lines.push(`Temperature: ${alert.temperature.toFixed(1)} °C`);
  }
  if (typeof alert.humidity === "number" && alert.humidity !== 0) {
    lines.push(`Humidity: ${alert.humidity.toFixed(0)} %`);
  }
  const lat = alert.latitude;
  const lng = alert.longitude;
  if (typeof lat === "number" && typeof lng === "number" && (lat !== 0 || lng !== 0)) {
    lines.push(`Location: https://maps.google.com/?q=${lat.toFixed(6)},${lng.toFixed(6)}`);
  }
  lines.push("Automatic alert from Forest Fire Monitor.");
  return lines.join("\n");
}

/** Sends to each station; returns how many accepted the message. */
export async function notifyStations(
  botToken: string,
  stations: Station[],
  text: string,
  location: { latitude: number; longitude: number } | null,
): Promise<number> {
  const api = `https://api.telegram.org/bot${botToken}`;
  let delivered = 0;

  await Promise.all(
    stations.map(async (station) => {
      try {
        const response = await fetch(`${api}/sendMessage`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ chat_id: station.telegramChatId, text, disable_web_page_preview: true }),
        });
        if (!response.ok) {
          console.warn(`Telegram to ${station.name} failed: ${response.status} ${await response.text()}`);
          return;
        }
        delivered++;

        if (location) {
          await fetch(`${api}/sendLocation`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ chat_id: station.telegramChatId, ...location }),
          });
        }
      } catch (error) {
        console.warn(`Telegram to ${station.name} failed:`, error instanceof Error ? error.message : error);
      }
    }),
  );

  return delivered;
}
