# Forest Fire Monitor work log

Newest last. Each entry says what was done and how it was checked.

## 2026-10-18 — Production foundation

- Imported the existing single-node demo; added sign-in and roles, multiple nodes, history charts, exports.
- Firestore rules and indexes; moved to Firebase project `forest-fire-3d2f0` on the free Spark plan.
- Backend: first Cloud Functions, then a Python service (Spark has no functions), then **Cloudflare Workers**
  (free, always on). Weeks-old alerts no longer re-pushed.
- Per-second live feed (RTDB) and instant node alerts (`/alert`); camera class mapping fixed.
- ML fire-danger model replaced fixed weather thresholds; six-sensor detection; terrain-based Low/Medium/High; danger
  timeline; instant fire pop-up; nearby phones and fire services.

## 2026-10-19 — UI, ML on Indian data, map, APK

- Fire-danger model retrained on Indian data (NASA VIIRS + ERA5, 45 forests, 23 states): leave-states-out ROC AUC 0.848.
- Clean UI theme; plain-language Home and Alerts; 3-tab navigation; gradient 24 h risk chart.
- LoRa: `/lora` endpoint and signal card; receiver flashed (no antennas, nothing received).
- **Defect fixed:** an old unresolved alert silenced new fire alerts.
- **Defect fixed:** the fire pop-up waited on the alarm audio and never showed on the web.
- Web: versioned scripts and update banner. Satellite map Home with fire areas and vegetation; Data tab.
- Tap-to-place sensors; floating live panel; fire areas only after 2 minutes of fire; critical push on confirmation.
- Fullscreen with safe areas; alarm channel and sound on Android; alarm test.
- Android APK built and signed; **defect fixed:** empty sensor list in the APK; in-app updates from the Worker.
- Node: camera AI 16 s → 2.7 s with ESP-NN; camera frames every 3 s; self-healing Wi-Fi and watchdog.

## 2026-10-20 — Reliability, alerts and reports

- Node: MQ-2 floating input found (second sensor not fitted) → fault detection and baseline scoring; serial Wi-Fi
  commands; hotspot over DHCP; chosen-network retries (fallback verified at ≈130 s).
- **Defect fixed:** offline alerts after the first outage.
- Directions to sensors and fires (1.0.4, confirmed by the user).
- Fire alerts only from 75% camera confidence (backend; node firmware updated later).
- Sensor details page; board health report every 30 s (flashed, verified in RTDB) (1.0.5).
- Real fire / False alarm, camera accuracy, sensor-problem alerts, fire stations, add sensor (1.0.6).
- Telegram bot connected; Telegram alerts for users; sign-up as viewer (1.0.7, confirmed by the user).
- Package renamed to `io.github.surendar77.forestfire`; privacy policy; private source repo and public download
  page (1.0.8).
- Graph zoom/pan and CSV export; alert timeline and Reports; plain message on every alert; air at the sensor (1.0.9).
- Documentation set modelled on PRISM-Endo; commit history cleaned of AI co-author lines.
