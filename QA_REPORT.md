# QA Report — Forest Fire Monitor

Date: 2026-10-20 · Scope: app (Android + web), backend Worker, security rules, sensor node.

## 1. Summary

| Suite | Tool | Tests | Result |
|---|---|---|---|
| App unit + widget | `flutter test` | 44 | all pass |
| Backend unit | `node --test` (worker) | 87 | all pass |
| Security rules | Firebase emulator (`rules-tests/`) | 23 | not re-run in this round (needs Java 11+ and the emulator) |
| Static analysis | `flutter analyze`, `tsc --noEmit` | — | no issues |
| End to end on hardware | NODE-01 + phone | manual | see §3 |

```powershell
flutter test ; flutter analyze
cd worker ; npm run typecheck ; npm test
cd rules-tests ; npm test
```

## 2. Automated coverage

| Area | What is checked |
|---|---|
| Alert rules | 75% fire / 50% smoke thresholds, severity from sensors and danger, low-confidence ignored |
| Repeats | recent-only blocking, streak, 150 s gap, 2-minute confirmation |
| Outages | offline alert resolves when the node reports after it |
| Health alerts | camera silent, sensor fault after 10 min, brownout once per restart, battery, Wi-Fi, chip, stale report ignored |
| Messages | fire/smoke/anomaly/satellite/offline/risk wording, zero readings omitted |
| Air at the sensor | clean, slight, smoke, heavy smoke, gas, learning, no reading, low-confidence camera |
| ML and maps | fire danger index, FFMC/ISI, terrain factors, spread ellipse, FIRMS parsing |
| Admin | add-sensor validation, random keys, Telegram updates and commands |
| App models | node/alert parsing, verdicts, timeline order and durations, report medians and false-alarm share |
| App widgets | sensor details (health, battery, no report), fire danger card, LoRa card, camera-accuracy card |
| Exports | readings CSV order and columns |

## 3. Verified on the real system

| Check | Result |
|---|---|
| Test fire alert via `/alert` → push on phone | received (2026-10-20) |
| Board health report written every 30 s | yes; backend health job read it (no issues) |
| Air status computed from a real reading | "Clean air" (2026-10-20 10:13 UTC) |
| In-app Android update 1.0.3 → 1.0.4 → … → 1.0.9 | installed by the user |
| Directions on the phone | confirmed working by the user |
| Sign-up on the new app | confirmed working by the user |
| Wi-Fi fallback after a failed network | falls back after ≈130 s |

## 4. Defects found and fixed

| Severity | Defect | Fix |
|---|---|---|
| Critical | An old unresolved alert silenced every new fire alert | only recent open alerts block a new detection |
| Critical | Offline alert never raised again after one outage | judge outages by `lastSeen` vs the alert time; resolve automatically |
| High | Fire pop-up never appeared on the web (alarm audio promise hung) | pop-up no longer waits for the alarm |
| High | APK showed no sensors (saved default location read blocked loading) | location read with a timeout before subscribing |
| High | Random smoke values 155–3885 on MQ2 | second sensor not fitted: input was floating → `MQ2_INSTALLED false`, fault detection |
| High | Browsers kept an old web app | versioned script URLs, build-id update banner |
| High | Firebase Hosting refused the APK | APK served from Worker static assets; deploy script deletes executables |
| Medium | `version.json` / `pubspec.yaml` broken by a byte-order mark | write files without BOM |
| Medium | Notifications silent on Android | dedicated alarm channel with sound |
| Medium | Fire areas drawn for one-off detections | only after 2-minute confirmation |
| Medium | Telegram emoji 🔧 on fire alerts once every alert had a message | choose by alert type |
| Low | Graph labels too sparse when zoomed | labels follow the zoom level |

## 5. Known limitations

- Camera thresholds not validated on real fires (no field fire yet).
- No automated end-to-end browser tests; the web app is checked manually.
- Security-rules tests need Java and the emulator, so they are not run on every change.
- Details: [docs/TECHNICAL_GUIDE.md](docs/TECHNICAL_GUIDE.md#12-limitations).
