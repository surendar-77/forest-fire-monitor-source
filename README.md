# Forest Fire Monitor

Real-time forest fire detection and early warning for field officers.
ESP32-S3 sensor nodes report to ThingSpeak. A small Python service turns
readings into risk scores, alerts and push notifications. This Flutter app
(Android, iOS, web) shows every node, its trends, and the alert workflow.

Everything runs on Firebase's **free Spark plan**.

```
ESP32-S3 node ──► ThingSpeak ──► backend service (Python, always-on PC / Raspberry Pi)
                                   │  devices/{node}, readings, hourly, alerts
                                   ▼
                             Firestore ◄──► Flutter app (sign-in, roles, live data)
                                   │
                    backend service ──► FCM push to officers' phones and browsers
```

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
- `backend/` Python service. It replaces Cloud Functions, which need the paid
  Blaze plan. It handles ThingSpeak polling, push alerts, node health,
  escalation, role changes, cleanup and a heartbeat.
- `firestore.rules` security rules. `rules-tests/` holds their tests.
- `config/*.example.json` build-time keys (copy to `config/prod.json`)

## Develop

```sh
flutter pub get
flutter run -d chrome                     # or an Android device
flutter test && flutter analyze

cd backend && python -m unittest          # backend tests
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
5. **Run the backend on a machine that stays on.**
   - **Windows:** edit the key path in `backend\run_backend.bat` and
     double-click it. To run it unattended, add it to Task Scheduler with the
     trigger "At startup". It restarts itself if it crashes.
   - **Raspberry Pi or Linux:** use `backend/forest-fire-backend.service`
     (instructions are inside the file).

   If the service stops, every signed-in user sees a red "Alert service
   offline" banner within 15 minutes.
6. **Stop the old bridge.** Stop running `integrated_monitor.py` from
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

Rule of thumb: **up to 5 nodes**, and around **10 officers with the app open
all day**. To cut usage, raise `POLL_SECONDS` (e.g. 120 halves the writes and
live reads). Check usage under Firebase console → Firestore → Usage.

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
