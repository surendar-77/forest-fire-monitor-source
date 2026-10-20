# Forest Fire Monitor — Technical guide (architecture, commands, measurements and status)

> **Field prototype. Not a certified fire-detection or life-safety system.**
> Alerts depend on Wi-Fi, mains/USB power and free cloud services, any of which can fail.
> The fire-danger rating is a statistical model trained on satellite fire detections, not a forecast of ignitions.

Forest Fire Monitor turns low-cost ESP32-S3 sensor nodes into a fire early-warning network. Each node
runs a camera AI on the device, two temperature/humidity sensors and a smoke sensor. A free cloud backend
scores every reading, raises alerts and sends push notifications; a Flutter app (Android and web) shows the
sensors on a satellite map with live readings, estimated fire areas, fire-danger forecasts, alerts and reports.

Everything runs on free plans: Firebase **Spark**, Cloudflare **Workers Free**, ThingSpeak free, NASA FIRMS,
Open-Meteo and Esri/NASA map tiles.

---

## 1. Architecture

```
ESP32-S3 node (firmware outside this repo, see [HARDWARE.md](HARDWARE.md))
  ├─ camera AI: ESP32-CAM → 240×240 JPEG every 3 s → TFLite Micro + ESP-NN on the S3 (≈2.7 s/frame)
  ├─ DHT22 × 2 (zones 1, 2) every 2.5 s · MQ-2 smoke every 1 s (16-sample average, fault detection)
  ├─ every 1 s  ──► Realtime Database live/{node}        ──► app: live panel, sensor details
  ├─ every 30 s ──► Realtime Database health/{node}      ──► app: power, Wi-Fi, board health
  ├─ fire/smoke ──► Worker POST /alert                   ──► push in ~2 s
  └─ every 60 s ──► ThingSpeak ──► Worker (every minute)
                                     │ risk score, anomaly score, air at the sensor, alert decision
                                     ▼
                                 Firestore: devices · readings · hourly · alerts · users
                                     │
        Cloudflare Worker crons ─────┤ push (FCM) · Telegram (users, fire stations) · node health
        (worker/src/index.ts)        │ sensor-problem alerts · escalation · fire danger (ML, hourly)
                                     │ satellite fires (NASA FIRMS) · rollups · retention · admin requests
                                     ▼
                     Flutter app (lib/) — Android APK + web (Firebase Hosting)
```

| Folder | Content |
|---|---|
| `lib/` | Flutter app: screens, widgets, models, services, utils |
| `lib/screens/` | Home map, Data (graphs), Alerts, Reports, Settings, sign-in/sign-up, Add sensor, Fire stations |
| `lib/services/` | node repository (Firestore streams), auth, push, history, report export, app update |
| `lib/utils/` | fire areas, alert timeline, alert report, plain-language labels |
| `worker/` | **backend**: Cloudflare Worker (TypeScript) with crons, `/alert`, `/lora`, APK hosting |
| `worker/src/` | ingest, alert rules, health alerts, alert messages, air at the sensor, fire danger, spread, FCM, Telegram |
| `backend/` | the same backend as a Python service + admin CLI (self-host alternative; run **either** this **or** the Worker) |
| `ml/` | fire-danger model training on Indian data (see [`ml/README.md`](../ml/README.md)) |
| `firestore.rules`, `database.rules.json` | security rules; `rules-tests/` holds their tests |
| `web/` | web shell, service worker, privacy policy |
| `tool/` | `deploy_web.ps1` (web release), `release_apk.ps1` (APK release + in-app update) |
| `docs/` | this guide, hardware, alerts, deployment, data formats, reports (see the README's documentation table) |
| `test/` | Flutter unit and widget tests |

---

## 2. Environment setup

Tested on Windows 11 with Flutter 3.47 / Dart 3.13, Node 22, Python 3.11 (ML) and Arduino IDE 2 with ESP32 core 3.3.11.

```powershell
flutter pub get
flutter run -d chrome                         # or an Android device
flutter test ; flutter analyze

cd worker ; npm ci ; npm test                  # backend tests
cd rules-tests ; npm ci ; npm test             # security-rules tests (needs Java 11+)
cd backend ; python -m unittest                # Python backend tests (optional)
```

Android builds need NDK `28.2.13676358` (`sdkmanager "ndk/28.2.13676358"`) and a release keystore
(`android/key.properties`, gitignored). Full cloud setup: **[DEPLOYMENT.md](DEPLOYMENT.md)**.

---

## 3. Sensors and data status

| Sensor | Fitted on NODE-01 | Rate | Notes |
|---|---|---|---|
| Camera (ESP32-CAM, AI on the S3) | ✅ | 1 photo / 3 s, 1 result / ≈2.7 s | classes Fire / Normal / Smoke |
| DHT22 zone 1, zone 2 | ✅ ✅ | 2.5 s | the DHT22 cannot be read faster |
| MQ-2 smoke sensor 1 | ✅ | 1 s | baseline-relative scoring after warm-up |
| MQ-2 smoke sensor 2 | ❌ (`MQ2_INSTALLED false`) | — | an unconnected ADC pin reads noise |
| Battery / charging | ❌ (`BATTERY_PIN -1`) | — | wiring in [HARDWARE.md](HARDWARE.md) |
| LoRa RA-02 (433 MHz) | ✅ with antennas | every 2.5 s + after each AI result | all data relayed by the gateway (10 dBm) |

| Data | Status |
|---|---|
| Live readings (per second) | ✅ RTDB `live/{node}` |
| Board health (power, Wi-Fi, memory, sensors) | ✅ RTDB `health/{node}`, every 30 s |
| History for graphs | ✅ ThingSpeak → Firestore `readings` (raw, 30-day retention) and `hourly` |
| Responder verdicts (real fire / false alarm) | ✅ collected on alerts; too few yet to retrain the camera model |
| Camera photos in the cloud | ❌ by design: only AI results leave the node (LoRa cannot carry images) |

---

## 4. Detection and risk (per reading)

* **Camera AI** — a TFLite Micro classifier on the S3. A **fire alert needs ≥ 75% confidence**; smoke needs ≥ 50%.
  The node sends fire/smoke alerts straight to the Worker (`/alert`); the Worker rejects fire alerts under 75%.
* **Anomaly score** — each node learns its own normal range per sensor (median and spread per hour) and
  scores how far smoke is above, temperature above and humidity below normal (`worker/src/anomaly.ts`).
* **Risk score 0–100** — camera, anomaly score, today's fire danger and the terrain combined (`worker/src/terrain.ts`).
* **Air at the sensor** — from the MQ-2 against its learned clean-air level, with the camera and heat/dryness
  deciding between smoke and gas (an MQ-2 reacts to both) (`worker/src/localAir.ts`):

| Status | Rule (z = deviation above normal) |
|---|---|
| Clean air | smoke z < 2 |
| Slightly unusual air | 2 ≤ z < 4, camera clear |
| Smoke detected | z ≥ 2 with camera smoke, or z ≥ 4 with camera smoke or rising heat/dryness |
| Heavy smoke | z ≥ 7 with camera smoke or heat |
| Gas detected | z ≥ 4, camera clear and no heat (LPG, methane, exhaust, alcohol) |
| Learning | first hour, baseline not ready |

## 5. Alerts

Every alert carries a plain message (what was seen, how sure, readings, what to do), shown in the push
notification, on Telegram, in the fire pop-up and in the app. Full rules: **[ALERTS.md](ALERTS.md)**.

| Type | Raised when |
|---|---|
| Fire (camera) | camera ≥ 75% sure; **confirmed + critical** after 2 min without a break |
| Smoke (camera) | camera ≥ 50% sure |
| Unusual sensor readings | anomaly level LIKELY |
| Satellite fire nearby | NASA FIRMS VIIRS detection within range of the node |
| Sensor offline | no data for 10 min; resolves itself when data returns |
| Sensor problems | camera silent 10 min, a sensor not reading 10 min, brownout restart, battery ≤ 20%, Wi-Fi < −80 dBm for 15 min, chip ≥ 80 °C; resolve themselves |

Responders acknowledge, mark **Real fire / False alarm** and resolve with an outcome. Each alert keeps a
timeline (detected → notified → confirmed → acknowledged → verdict → resolved).

## 6. Fire danger and spread (ML)

Hourly, per node: gradient-boosted trees trained on NASA FIRMS fires and ERA5 weather for 45 Indian forest
areas give today's chance of a fire within 10 km, mapped to Low / Medium / High, plus the riskiest hour in the
next 24 h. A Rothermel/FBP-style ellipse estimates where a confirmed fire could spread in the next hour.
Details and evaluation: **[`ml/README.md`](../ml/README.md)**.

## 7. The app

| Screen | What it shows |
|---|---|
| Home | satellite / vegetation / street map, sensors, fire areas, live panel (readings, camera, risk, **air at sensor**, fire prediction), directions |
| Sensor details (tap a sensor) | live readings, power and restarts, Wi-Fi, board, sensor and camera health, place |
| Data | graphs (pinch to zoom, drag to move) for temperature, humidity, smoke, camera, risk; AI predictions; fire weather; **CSV download** |
| Alerts | open / resolved, filters, verdict buttons, camera-accuracy card, timeline |
| Reports | 7/30/90 days per sensor: totals, response times, false alarms, alerts per day, every alert's timeline, **PDF / CSV** |
| Settings | alerts, nearby alerts, Telegram, alarm test, default location; admins: add a sensor, fire stations, roles |

| Role | Can |
|---|---|
| Viewer (every new sign-up) | see sensors, locations, readings and alerts; get notifications |
| Officer | also acknowledge, judge and resolve alerts; download reports |
| Admin | also add sensors, set locations and terrain, manage fire stations, assign roles |

Roles are Firebase Auth custom claims enforced by `firestore.rules`.

## 8. Releases

```powershell
# web (stamps a build id so installed copies show "update available")
powershell -ExecutionPolicy Bypass -File tool\deploy_web.ps1

# Android: bump `version:` (+N must increase) in pubspec.yaml, then
powershell -ExecutionPolicy Bypass -File tool\release_apk.ps1 -Notes "What changed"
```

The APK (arm64, ≈23 MB, package `io.github.surendar77.forestfire`) is served from the Worker's static
assets (Firebase Hosting on Spark refuses executables); installed apps compare their build number with
`/apk/version.json` and offer the update. Public downloads: github.com/surendar-77/forest-fire-monitor.

## 9. Tests

```powershell
flutter test                      # 44 tests (2026-10-20)
cd worker ; npm test              # 87 tests (2026-10-20)
```

Covered: alert rules and thresholds, repeat-detection confirmation, outage handling, health alerts, alert
messages, air at the sensor, fire danger, spread, terrain, FIRMS parsing, LoRa, Telegram parsing, add-sensor
validation; app models, fire areas, sensor-details page, camera accuracy, timeline, reports, CSV export.

## 10. Measured on NODE-01 (2026-10-20)

| What | Measured |
|---|---|
| Camera AI inference on the S3 | ≈2.7 s per frame (ESP-NN; 16 s without) |
| Fire alert to phone | ≈2 s (node → Worker → FCM) |
| Live feed | 1 update/s; cloud uploads 99%+ delivered on a good Wi-Fi link |
| Fire-danger model (leave-states-out) | ROC AUC 0.848, PR AUC 0.176 ([`ml/README.md`](../ml/README.md)) |
| Board free memory / chip temperature | ≈151 KB heap, ≈40 °C indoors |

## 11. Free-plan limits

Spark allows 50,000 reads, 20,000 writes and 20,000 deletes per day; going over **pauses Firestore until the
reset**. Rule of thumb: **up to 5 nodes and ~10 people with the app open all day** (per node ≈2,900 writes and
≈1,440 deletes a day; each app start ≈100 reads). Workers Free: 100,000 requests/day, 50 sub-requests per run,
5 cron triggers. Details: **[DEPLOYMENT.md](DEPLOYMENT.md)**.

## 12. Limitations

* **One node, one site so far.** Thresholds and the camera model have not been validated on real forest fires.
* **Camera AI is a small classifier** on 240×240 frames; sun glare, red objects and fog can fool it. The 75%
  threshold and the 2-minute confirmation reduce false alarms but do not remove them.
* **MQ-2 cannot tell smoke from gas by itself**; "Gas detected" is an inference from the camera and heat sensors.
* **Fire danger** rates conditions, not ignitions; most Indian forest fires are lit by people.
* **Connectivity**: Wi-Fi only until the LoRa gateway is finished; a node without Wi-Fi cannot alert.
* **Free services**: public routing (OSRM) and map tiles are rate-limited; Firebase Spark has hard daily quotas.
* **Security**: RTDB device writes are authorised by a per-node key in the firmware (see [HARDWARE.md](HARDWARE.md)).

---

## 13. Update 2026-10-20 — status

| Item | State |
|---|---|
| Live map, sensor details, directions, graphs with zoom, CSV export | Implemented, tested, released (APK 1.0.9) |
| Alerts with messages, verdicts, camera accuracy, timeline, reports | Implemented, tested, released |
| Sensor-problem alerts from board health | Implemented, tested, running |
| Air at the sensor (clean / smoke / gas) | Implemented, tested, running |
| Telegram for users and fire stations | Implemented; bot connected; stations to be added |
| Sign-up (viewers), add sensor, fire stations admin | Implemented, released |
| LoRa receiver gateway (all data, backup when Wi-Fi fails) | Implemented, tested on hardware (Wi-Fi-off test passed) |
| Over-the-air firmware updates | **Designed, not built** |
| Camera model retraining from verdicts (ML stage 3) | **Pending** (needs labelled events) |
| iOS build | **Not built** (needs an Apple developer account and a Mac) |

### Next required actions

1. Range-test LoRa in the forest (10 dBm, SF7); consider SF9-10 for longer range.
2. Power the node from a 5 V 2 A supply or battery + solar; wire the battery sensor.
3. Collect Real fire / False alarm verdicts, then retrain the camera model and re-check the 75% threshold.
4. Close the RTDB device-key gap with Worker-minted tokens; rotate old keys; delete the old Firebase project.
5. Move routing to OpenRouteService (free key) before wider use.
