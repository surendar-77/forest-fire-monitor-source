# Deployment (all free plans)

## 1. Firebase (Spark)

1. **Authentication** → enable Email/Password. Sign-up is open; new accounts are viewers.
2. **Firestore** and **Realtime Database** (Singapore, locked mode).
3. Rules:

```powershell
firebase deploy --only firestore:rules
firebase deploy --only database
```

4. **Service-account key**: Project settings → Service accounts → Generate new private key. Store it outside
   the repo (e.g. `C:\secure\…json`). Never commit it.
5. First admin (from `backend/`): `python -m forest_fire_backend.manage grant-role you@example.org admin`.
   After that, admins assign roles in the app (Settings → Set a user's role).

## 2. Backend (Cloudflare Workers Free)

```powershell
cd worker
npm ci
npx wrangler login
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT < C:\secure\<service-account>.json
npx wrangler secret put TELEGRAM_BOT_TOKEN        # optional: @BotFather token
npx wrangler secret put FIRMS_MAP_KEY             # optional: NASA FIRMS key for satellite fires
npx wrangler deploy
npx wrangler tail                                 # live logs
```

`wrangler.jsonc` vars: `READING_RETENTION_DAYS` (30), `RTDB_URL`. Crons (the free plan allows 5):

| Cron | Job |
|---|---|
| `* * * * *` | ingest every ThingSpeak channel |
| `*/1 * * * *` | push new alerts, admin requests, Telegram inbox |
| `*/5 * * * *` | node health, board-health alerts, roles, heartbeat, escalation |
| `7 * * * *` | hourly rollup, fire danger, satellite fires |
| `23 21 * * *` | delete readings past retention (03:00 IST) |

If the backend stops, every signed-in user sees "Alert service offline" within 15 minutes (heartbeat).

## 3. Sensors

* Each sensor needs a ThingSpeak channel (8 fields) for history and status.
* Add it in the app (admin): Settings → **Add a sensor**. The backend creates `devices/{id}`, the device key
  (Firestore `config/deviceKeys` and RTDB `deviceKeys/{id}`) and the channel entry, then shows the `NODE_ID` /
  `NODE_KEY` lines for the firmware once.
* Place it on the map (pin button) and set its terrain.

## 4. Web app (Firebase Hosting)

```powershell
powershell -ExecutionPolicy Bypass -File tool\deploy_web.ps1
```

The script stamps a build id (installed copies show "update available"), versions the script URLs and refuses
to upload executables (Spark rejects them). Privacy policy: `web/privacy.html` → `/privacy.html`.

## 5. Android

* Keystore outside the repo; `android/key.properties` (gitignored) points to it. **Every update must use the
  same key**, or phones refuse to install it.
* Package: `io.github.surendar77.forestfire` (Firebase Android app registered for it).

```powershell
# bump `version: X.Y.Z+N` in pubspec.yaml (N must increase), then
powershell -ExecutionPolicy Bypass -File tool\release_apk.ps1 -Notes "What changed"
gh release create vX.Y.Z $env:USERPROFILE\Downloads\ForestFireMonitor-X.Y.Z.apk --repo surendar-77/forest-fire-monitor
```

`release_apk.ps1` builds the arm64 APK (must stay under 25 MiB), writes `version.json` (UTF-8 **without** BOM),
copies both to `worker/public/apk` and redeploys the Worker, which serves them. Installed apps compare their
build number and offer the update.

## 6. Quotas

| Spark (per day) | Limit | Typical use per node |
|---|---|---|
| Firestore reads | 50,000 | backend ≈4,500; each app start ≈100; one app open all day ≈1,440 |
| Firestore writes | 20,000 | ≈2,900 (readings, device, hourly) |
| Firestore deletes | 20,000 | ≈1,440 (30-day retention) |
| RTDB download | 10 GB/month | live feed is pushed, not polled |

Going over a Firestore quota **pauses it until the reset**. Rule of thumb: up to 5 nodes and ~10 people with the
app open all day. Workers Free: 100,000 requests/day, 50 sub-requests per run (one push run reaches ≈45 phones).

## 7. Secrets checklist

| Secret | Where it lives |
|---|---|
| Firebase service account | `C:\secure\…`, Worker secret `FIREBASE_SERVICE_ACCOUNT` |
| Telegram bot token | Worker secret `TELEGRAM_BOT_TOKEN` (revoke with `/revoke` in @BotFather if leaked) |
| Node keys | firmware + `config/deviceKeys` + RTDB `deviceKeys` |
| ThingSpeak write key, Wi-Fi passwords | firmware only |
| Android keystore + passwords | `C:\secure\…`, `android/key.properties` (gitignored) |
