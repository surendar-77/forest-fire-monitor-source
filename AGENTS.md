# AGENTS.md — rules for AI coding agents

Read this before changing Forest Fire Monitor.

## Ground rules

1. **Safety and honesty first.** Never lower an alert threshold, remove a confirmation step or suppress a
   sensor-problem alert without saying so in the docs. Never report a detection rate that was not measured.
2. **No certification claims.** Keep the field-prototype disclaimer. The fire-danger level rates conditions, not
   ignitions; "Gas detected" is an inference.
3. **Never commit secrets**: service-account keys, the Telegram token, node keys, the ThingSpeak write key, Wi-Fi
   passwords, the Android keystore or `android/key.properties`. Firmware stays outside the repository.
4. **Stay inside the free plans.** Firestore Spark pauses when a daily quota is exceeded: count reads/writes for
   every new query or job, prefer one query per run, and never poll per second from the app.
5. **Workers Free: 50 sub-requests per run.** Use `budget(ctx)` before loops that call Firestore, FCM or Telegram.
6. **No Claude / AI co-author lines** in commits, PRs or docs.

## Before you finish a change

```powershell
flutter analyze ; flutter test          # must stay clean and green
cd worker ; npm run typecheck ; npm test
cd rules-tests ; npm test               # when firestore.rules changes
```

Deploy order: rules (`firebase deploy --only firestore:rules` / `database`) → Worker (`npx wrangler deploy`) →
web (`tool\deploy_web.ps1`) → Android (`tool\release_apk.ps1`, bump `version:` first).

## Conventions

- **Dart:** match the surrounding style; plain-language UI text (see [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md));
  shared labels in `lib/utils/friendly.dart`; pure logic in `lib/utils/` with tests.
- **TypeScript (worker):** pure, tested modules (`health.ts`, `localAir.ts`, `alertMessages.ts`, …) called from
  `index.ts`; wrap side effects in `run(name, …)` so one failure doesn't stop a job.
- **New alert types:** add the rule + message + test in the worker, the title/icon in `friendly.dart`, the push
  title in `fcm.ts`, and a row in [docs/ALERTS.md](docs/ALERTS.md).
- **New RTDB fields from the node:** add validation in `database.rules.json` (unknown fields are rejected).
- **Files written by scripts:** UTF-8 **without** BOM (PowerShell `Set-Content -Encoding utf8` adds one and broke
  `pubspec.yaml` and `version.json` before).
- **Windows paths:** quote paths with spaces; this repo lives in `forest_fire_monitor_FINAL_source - Copy`.

## Where things are

See [ARCHITECTURE.md](ARCHITECTURE.md) for components and data flow, and
[docs/TECHNICAL_GUIDE.md](docs/TECHNICAL_GUIDE.md) for every command and measurement.
