# Forest Fire Monitor — complete inventory of work done (as of 2026-10-20)

Everything below was verified against files in the project or on the live system. "Before" = what existed when
the production work started on 2026-10-18.

## 0. What existed before

| Item | State found |
|---|---|
| Flutter app | single-node demo: one hard-coded Firestore document `devices/NODE-01`, no sign-in |
| Security | anyone could write the database |
| Simulation mode | wrote **fake alerts into the real `alerts` collection** |
| Push | one token per node (each phone overwrote the last); nothing actually sent pushes |
| Data path | ESP32 → ThingSpeak → Python bridge on a laptop → Firestore (stopped when the laptop slept) |
| Risk | fixed thresholds on a 0–12 scale |
| Node | camera AI took ≈16 s per frame; one MQ-2 input floating |

## 1. Backend

1. Cloudflare Worker backend, free and always on: ingestion, push, node health, escalation, roles, rollups,
   retention, heartbeat (`worker/`). Python equivalent kept for self-hosting (`backend/`).
2. Per-second live feed and 30 s health in the Realtime Database with validating rules.
3. Alert rules: 75% fire / 50% smoke, recent-only blocking, 2-minute confirmation, outage logic.
4. Anomaly scoring against each node's learned baseline; risk 0–100 with terrain.
5. Plain message on every alert; sensor-problem alerts; air at the sensor.
6. Fire danger ML (Indian data) and fire-spread estimate; NASA FIRMS satellite fires.
7. Push (FCM) with alarm channel, nearby phones, escalation; Telegram for users and fire stations.
8. Admin requests: add sensor with a random key, test station, set role.
9. APK hosting and in-app update feed from Worker static assets.

## 2. App

1. Sign-in, open sign-up as viewer, roles (viewer / officer / admin).
2. Satellite / vegetation / street map, sensors, fire areas, live panel with air status and fire prediction.
3. Sensor details: live readings, power, Wi-Fi, board and sensor health.
4. Directions with navigation; tap-to-place sensors; add sensor; fire stations; Telegram link.
5. Data graphs with zoom/pan, AI prediction chart, fire weather, CSV export.
6. Alerts with messages, verdicts, camera accuracy, timeline; Reports with PDF/CSV.
7. Fire pop-up with alarm; notifications on Android and web; update banners.
8. Android APK (arm64, ≈23 MB) with in-app updates; web app on Firebase Hosting.

## 3. Sensor node

1. Camera AI with ESP-NN (16 s → 2.7 s); camera frames every 3 s.
2. MQ-2: 16-sample averaging, fault detection, baseline-relative scoring; second sensor disabled.
3. Self-healing Wi-Fi with backup and saved networks, serial Wi-Fi commands, watchdog, restart on fatal errors.
4. Board health report (restart reason, start count, Wi-Fi, memory, chip temperature, sensors, optional battery).
5. Fire alerts sent directly to the backend.

## 4. Quality, security, docs

1. 44 app tests and 87 backend tests; security-rules tests.
2. Secrets kept out of the repo; firmware outside the repo; private source repo, public download page.
3. Privacy policy; documentation set (README, PRD, architecture, agents, design system, QA, downloads, guides, reports).

## 5. Open items

LoRa gateway (antennas), field validation on real fires, camera retraining from verdicts, device tokens instead
of keys, reliable power, iOS, OTA firmware updates.

## 6. Comparison table: before vs now

| Area | Before | Now |
|---|---|---|
| Sensors supported | one, hard-coded | any number, added from the app |
| Backend | laptop script | free cloud Worker, always on |
| Alerts reach phones | only with the app open | push in ≈2 s, alarm sound, Telegram |
| False-alarm control | none | 75% threshold, 2-minute confirmation, baselines, verdicts |
| Alert content | type only | plain message with confidence, readings and next step |
| Broken sensor | invisible | alert within 10 minutes |
| Fire danger | fixed thresholds | ML model, ROC AUC 0.85 on unseen states |
| Camera AI | ≈16 s per frame | ≈2.7 s per frame |
| Accounts | none | sign-up, roles, enforced by rules |
| Updates | reinstall by hand | in-app updates (Android, web) |
| Reports | none | timeline, reports, PDF/CSV, graph CSV |
| Running cost | — | free plans |
