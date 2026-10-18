# Forest Fire Monitor

Real-time forest fire detection and early warning for field officers.
ESP32-S3 sensor nodes report to ThingSpeak; a Firebase backend turns readings
into risk scores, alerts and push notifications; this Flutter app (Android,
iOS, web) shows every node, its trends, and the alert workflow.

```
ESP32-S3 node ──► ThingSpeak ──► Cloud Function pollThingSpeak (every minute)
                                   │  devices/{node}, readings, hourly, alerts
                                   ▼
                             Firestore ──► onAlertCreated ──► FCM push
                                   ▲
                    Flutter app (sign-in, roles, live data, acknowledge/resolve)
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
  - `services/node_repository.dart` streams all nodes and alerts
  - `services/auth_service.dart` sign-in and roles
  - `services/fcm_service.dart` per-user push tokens
- `functions/` Cloud Functions (TypeScript): ingestion, node health, push,
  escalation, roles
- `firestore.rules`, `firestore.indexes.json` security rules and indexes
- `config/*.example.json` build-time keys (copy to `config/prod.json`)

## Develop

```sh
flutter pub get
flutter run -d chrome                     # or an Android device
flutter test && flutter analyze

cd functions && npm ci && npm test        # backend unit tests
npm run test:rules                        # needs Java 11+ (Firestore emulator)
```

## First deployment (one-time setup)

1. **Firebase plan.** Upgrade the project to Blaze (pay-as-you-go).
   Scheduled functions require it. Usage at this scale stays within the free
   allowance.
2. **Firebase CLI.** Run `npm install -g firebase-tools`, then `firebase login`.
3. **Authentication.** In the Firebase console, go to Authentication and
   enable Email/Password. Add each officer's account under Users.
4. **Deploy the backend.** From the repo root:
   ```sh
   firebase deploy --only firestore,functions
   ```
5. **Point ingestion at your nodes.** Create the Firestore document
   `config/channels`:
   ```json
   { "channels": [ { "nodeId": "NODE-01", "channelId": "3444282", "name": "Forest Node 01" } ] }
   ```
   Add `"readApiKey"` for private channels, and one entry per node.
6. **First administrator.** Run this with a service-account key that is kept
   outside the repo:
   ```sh
   cd functions
   set GOOGLE_APPLICATION_CREDENTIALS=C:\secure\service-account.json
   npm run grant-admin -- you@example.org
   ```
   After that, admins assign roles in the app under Settings → Set a user's role.
7. **Readings retention.** The 30-day TTL on `readings.expireAt` is declared
   in `firestore.indexes.json`. Confirm it is active under Firestore → TTL.
8. **Stop the laptop bridge.** Once `pollThingSpeak` is live, stop running
   `integrated_monitor.py`. If you keep it, note that it writes `riskScore` on a
   0–12 scale while the app expects 0–100.

## Release builds

Copy `config/prod.example.json` to `config/prod.json` and fill in the keys.

```sh
# Android (create android/key.properties first; see android/app/build.gradle.kts)
flutter build appbundle --release --dart-define-from-file=config/prod.json

# Web control-room dashboard → Firebase Hosting
flutter build web --release --dart-define-from-file=config/prod.json
firebase deploy --only hosting

# iOS (on a Mac with Xcode)
flutter build ipa --release --dart-define-from-file=config/prod.json
```

Before the first store release:

- **App ID.** Replace `com.example.forest_fire_monitor` with your own ID
  (`android/app/build.gradle.kts` and the iOS bundle ID), then re-run
  `flutterfire configure` so Firebase knows the new ID.
- **iOS push.** In Xcode, add the Push Notifications and Background Modes
  capabilities to Runner. Upload an APNs key in Firebase → Cloud Messaging.
- **Web push.** Create a Web Push certificate in Firebase → Cloud Messaging
  and put the key in `WEB_PUSH_VAPID_KEY`.
- **Maps.** Get MapTiler (tiles) and OpenRouteService (routing) keys. The
  public OSM and OSRM servers are for development only.
- **Secrets.** Rotate the Firebase Admin service-account key and the
  ThingSpeak write key. Both have been stored in plain files and zips.
