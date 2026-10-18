# Forest Fire Monitor

Real-time forest fire detection and early warning for field officers.
ESP32-S3 sensor nodes report to ThingSpeak. A backend turns readings into
risk scores, alerts and push notifications. This Flutter app (Android, iOS,
web) shows every node, its trends, and the alert workflow.

Everything is free: Firebase's **Spark** plan, plus a backend on
**Cloudflare Workers'** free plan (no credit card, always on, runs every
minute).

```
                ┌─ every 1 s ──► Realtime Database live/{node} ──► app live card
ESP32-S3 node ──┼─ fire/smoke ─► backend POST /alert ──► FCM push in ~2 s
                └─ every 60 s ─► ThingSpeak ──► backend (Cloudflare Worker, every minute)
                                                 │  devices, readings, hourly, alerts
                                                 ▼
                                           Firestore ◄──► Flutter app (sign-in, roles, history)
```

### Data timing

| What | How often | Where |
|---|---|---|
| Smoke sensors (MQ-2) | every 1 s | live feed |
| Temperature / humidity (DHT22) | every 2.5 s (the DHT22 can't be read faster; swap in an SHT31/SHT40 for 1 s) | live feed |
| Camera AI | every ~15 s (on-device inference time) | live feed, instant alert |
| History for charts | 60 s summary with the worst value of each sensor | ThingSpeak → Firestore |
| Fire, smoke or high-risk alert | immediately, decided on the node | backend → push |

ThingSpeak's free plan can't take per-second data (15 s minimum, about 3
million messages a year), so per-second values go to the Firebase Realtime
Database, which charges for data downloaded, not per write.

## Roles

| Role | Can |
|---|---|
| Viewer (default) | See nodes, map, trends and alerts |
| Officer | Also acknowledge and resolve alerts, export reports |
| Admin | Also set node locations, assign roles, use simulation mode |

Roles are Firebase Auth custom claims, enforced by `firestore.rules`.

## Project layout

- `lib/` Flutter app
  - `services/node_repository.dart` streams all nodes and alerts, plus the
    backend heartbeat
  - `services/auth_service.dart` sign-in and roles
  - `services/fcm_service.dart` per-user push tokens
- `worker/` the **backend**, as a Cloudflare Worker (TypeScript). It handles
  ThingSpeak polling, push alerts, node health, escalation, role changes,
  hourly rollups, cleanup and a heartbeat.
- `backend/` the same backend as a Python service, plus the admin command
  line (`manage`). Use it to self-host on a PC or Raspberry Pi instead of
  Cloudflare. Run **either** the Worker **or** this service, never both.
- `firestore.rules` security rules. `rules-tests/` holds their tests.
- `config/*.example.json` build-time keys (copy to `config/prod.json`)

## Develop

```sh
flutter pub get
flutter run -d chrome                     # or an Android device
flutter test && flutter analyze

cd worker && npm ci && npm test           # Worker backend tests
cd backend && python -m unittest          # Python backend tests
cd rules-tests && npm ci && npm test      # rules tests; needs Java 11+
```

## Setup

1. **Authentication.** In the Firebase console, go to Authentication and
   enable Email/Password. Add each officer's account under Users.
2. **Security rules.** From the repo root:
   ```sh
   npm install -g firebase-tools && firebase login
   firebase deploy --only firestore
   ```
3. **Service-account key.** In the Firebase console, go to Project settings →
   Service accounts → Generate new private key. Store the file **outside**
   this repo, e.g. `C:\secure\forest-fire-service-account.json`.
4. **Point the backend at your nodes and create the first admin.** From
   `backend/`:
   ```sh
   set GOOGLE_APPLICATION_CREDENTIALS=C:\secure\forest-fire-service-account.json
   pip install -r requirements.txt
   python -m forest_fire_backend.manage add-channel NODE-01 3444282 --name "Forest Node 01"
   python -m forest_fire_backend.manage grant-role you@example.org admin
   ```
   After that, admins assign roles in the app under Settings → Set a user's role.
5. **Deploy the backend to Cloudflare (free).** Create an account at
   https://dash.cloudflare.com/sign-up (no card needed). Then, from `worker/`:
   ```sh
   npm ci
   npx wrangler login
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT < C:\secure\forest-fire-service-account.json
   npx wrangler deploy
   npx wrangler tail          # live logs
   ```
   It runs every minute from then on, with nothing to keep switched on. If it
   ever stops, every signed-in user sees a red "Alert service offline" banner
   within 15 minutes.

   *Alternative:* run the Python service on a PC or Raspberry Pi that stays on
   (`backend\run_backend.bat`, or `backend/forest-fire-backend.service`).
6. **Per-second live feed and instant alerts.**
   - In the Firebase console, go to Realtime Database → **Create Database**.
     Choose **Singapore (asia-southeast1)** and start in **locked mode**.
   - Under Rules, paste in `database.rules.json` and click Publish.
   - Register the node and get its secret key (from `backend/`):
     ```sh
     python -m forest_fire_backend.manage add-device NODE-01 --database-url https://forest-fire-3d2f0-default-rtdb.asia-southeast1.firebasedatabase.app
     ```
   - Paste the printed `NODE_ID`, `NODE_KEY` and `RTDB_URL` lines into
     `ForestFire_S3.ino`, then compile and flash it.
7. **Stop the old bridge.** Stop running `integrated_monitor.py` from
   `forest_fire_integration_final/`. The new service replaces it, and the old
   one writes risk on a 0–12 scale.

## Staying inside the free quota

Spark gives 50,000 reads, 20,000 writes and 20,000 deletes per day. Going
over **pauses Firestore until the quota resets**, so the system is built to
stay well under:

| Usage | Per day |
|---|---|
| Each node, one reading per minute: device update + reading (+24 hourly rollups) | ~2,900 writes |
| Old-readings cleanup (30-day retention), per node | ~1,440 deletes |
| One app left open all day, per node | ~1,440 reads |
| Each app start | up to ~100 reads (newest alerts and nodes) |
| Each history view (1h / 24h / 7d) | ~60 / ~85 / ~170 reads |
| Backend: device checks, open alerts, hourly rollup (per node) | ~4,500 reads |

Rule of thumb: **up to 5 nodes**, and around **10 officers with the app open
all day**. Check usage under Firebase console → Firestore → Usage.

The Cloudflare free plan (100,000 requests a day, 50 outbound requests per
run) covers this. A single push run reaches up to about 45 devices.

## Release builds

Copy `config/prod.example.json` to `config/prod.json` and fill in the keys.

```sh
# Android (create android/key.properties first; see android/app/build.gradle.kts)
flutter build appbundle --release --dart-define-from-file=config/prod.json

# Web control-room dashboard → Firebase Hosting (free: 10 GB stored, 360 MB/day)
flutter build web --release --dart-define-from-file=config/prod.json
firebase deploy --only hosting

# iOS (on a Mac with Xcode)
flutter build ipa --release --dart-define-from-file=config/prod.json
```

Before the first store release:

- **App ID.** Replace `com.example.forest_fire_monitor` with your own ID, then
  re-run `flutterfire configure`.
- **iOS push.** In Xcode, add the Push Notifications and Background Modes
  capabilities. Upload an APNs key in Firebase → Cloud Messaging. This needs a
  paid Apple developer account.
- **Web push.** Create a Web Push certificate in Firebase → Cloud Messaging and
  put the key in `WEB_PUSH_VAPID_KEY`.
- **Maps.** Get MapTiler (tiles) and OpenRouteService (routing) keys. Both
  have free tiers. The public OSM and OSRM servers are for development only.
- **Secrets.** Rotate the old Firebase Admin service-account key and the
  ThingSpeak write key. Both have been stored in plain files and zips.
