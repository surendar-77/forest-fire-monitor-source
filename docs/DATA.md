# Data formats

## ThingSpeak (one channel per node, every 60 s)

| Field | Value |
|---|---|
| 1 / 2 | temperature / humidity, zone 1 (worst of the minute) |
| 3 / 4 | temperature / humidity, zone 2 |
| 5 / 6 | MQ-2 sensor 1 / 2 (blank when faulty or not fitted) |
| 7 | camera class: 0 Fire, 1 Normal, 2 Smoke |
| 8 | camera confidence (0–1) |

## Realtime Database

| Path | Written by | Content |
|---|---|---|
| `live/{node}/values` | node, every 1 s | `t1 h1 t2 h2 mq1 mq2 risk level ai conf up ts` |
| `health/{node}/info` | node, every 30 s | uptime, restart reason, starts, firmware, battery, Wi-Fi, memory, chip temperature, uploads, camera, sensors, LoRa (see `database.rules.json`) |
| `deviceKeys/{node}` | backend only | per-node secret checked by the write rules |

Reads need a signed-in user; writes need the node's key and pass field validation.

## Firestore

| Collection | Content |
|---|---|
| `devices/{node}` | name, zone, location, terrain, status, lastSeen, latest readings, risk, anomaly, `localAir`, `danger` (fire forecast), `lora`, hotspots, health issue tracking |
| `devices/{node}/readings` | one per minute: readings, camera class/confidence, risk, anomaly (deleted after 30 days) |
| `devices/{node}/hourly` | hourly rollups for the 24 h / 7 d graphs |
| `alerts/{id}` | type, severity, status, message, readings, timeline fields (`pushedAt`, `confirmedAt`, `ackAt`, `verdictAt`, `resolvedAt`, …), verdict, outcome, notes |
| `users/{uid}` | name, email, role mirror, followed sensors, Telegram link |
| `pushTokens/{token}` | owner, platform, optional location for nearby alerts |
| `fireStations/{id}` | name, Telegram chat, phone, optional location (admins) |
| `telegramChats/{chatId}` | who messaged the bot (admins read) |
| `adminRequests/{id}`, `roleRequests/{id}` | admin actions carried out by the backend |
| `config/*` | backend-only: channels, device keys, fire services |
| `status/backend` | heartbeat, Telegram bot status |

## CSV exports

**Graph data** (Data tab → CSV), oldest first, one row per reading (1H) or per hour (24H, 7D):

```
Time, Temperature zone 1 °C, Temperature zone 2 °C, Humidity zone 1 %, Humidity zone 2 %,
Smoke sensor 1 (MQ-2), Smoke sensor 2 (MQ-2), Camera fire %, Camera smoke %,
Camera AI class, Camera AI confidence %, Fire risk score
```

**Alerts** (Reports → CSV), newest first:

```
Alert ID, Node, Type, Severity, Status, Detected, Confirmed, Acknowledged by, Acknowledged at,
Minutes to acknowledge, Responder verdict, Resolved by, Resolved at, Minutes to resolve, Outcome,
Camera AI %, Fire %, Smoke %, Temperature °C, Humidity %, Latitude, Longitude, Details, Notes
```

Files start with a UTF-8 BOM so Excel shows °C correctly. The PDF report starts with a summary (totals,
typical response times, false-alarm share, breakdowns by type and sensor) followed by every alert.
