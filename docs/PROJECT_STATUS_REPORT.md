# Forest Fire Monitor — Project status report (2026-10-20)

Evidence is from files, test runs and the live system on the date above. Nothing here is estimated unless marked.

## 1. Executive summary

- One sensor node (NODE-01) runs camera AI, two DHT22s and one MQ-2, sending live values every second, health
  every 30 s and minute summaries to a free Cloudflare Worker backend.
- The Android app (1.0.9, package `io.github.surendar77.forestfire`) and the web app are released, update
  themselves, and cover the full flow: map → sensor details → alerts → verdict → resolution → reports.
- Every alert has a plain message; fire needs ≥ 75% camera confidence and is confirmed after 2 minutes.
- Tests: 44 app + 87 backend pass. A test fire alert reached the phone; sign-up and directions were confirmed by the user.
- Biggest gaps: no off-grid link yet (LoRa antennas missing), camera thresholds not validated on real fires,
  and the node relies on mains/USB power.

## 2. Completed work (with evidence)

| Item | Evidence |
|---|---|
| Free backend on Cloudflare Workers with 5 crons and `/alert`, `/lora` | `worker/src/index.ts`; heartbeat in `status/backend` |
| Per-second live feed and 30 s board health (RTDB) | `database.rules.json`; health report read by the backend 2026-10-20 |
| Fire alert rules (75% / 50%), repeat merge, 2-minute confirmation | `alertRules.ts`, tests |
| Plain message on every alert | `alertMessages.ts`, tests; shown in push, Telegram, app |
| Sensor-problem alerts (camera, sensors, power, battery, Wi-Fi, chip) | `health.ts`, tests |
| Air at the sensor (clean / smoke / gas) | `localAir.ts`, tests; "Clean air" on NODE-01 |
| Fire danger ML on Indian data | `ml/README.md`: leave-states-out ROC AUC 0.848 |
| Satellite map, live panel, sensor details, directions | app 1.0.4–1.0.9; user confirmed directions |
| Graphs with zoom/pan, CSV export; alert timeline; reports (PDF/CSV) | app 1.0.9; tests |
| Real fire / False alarm, camera accuracy card | app 1.0.6; tests |
| Telegram for users and fire stations | bot connected; `telegram.ts` tests |
| Sign-up (viewer), add sensor, fire stations admin | app 1.0.6–1.0.7; user confirmed sign-up |
| In-app Android updates; web update banner | 1.0.3 → 1.0.9 installed in place |
| Node: self-healing Wi-Fi, watchdog, serial Wi-Fi commands, MQ fault detection, health report | flashed 2026-10-19/20 |
| Privacy policy, public download page, private source repo | links in [DOWNLOAD_LINKS.md](../DOWNLOAD_LINKS.md) |

## 3. Partially completed

| Item | State |
|---|---|
| Telegram fire stations | bot ready; no station added yet |
| Camera accuracy | buttons and card live; one judged alert so far |
| LoRa | sender in firmware, receiver flashed; no antennas, so no packets received |
| Battery monitoring | firmware ready (`BATTERY_PIN`); hardware not wired |

## 4. Pending (no blocker other than time)

1. Health warning dot on map markers.
2. Tamil and Hindi; dark mode; offline map tiles.
3. Over-the-air firmware updates (design in the technical guide).
4. OpenRouteService routing key instead of the public OSRM server.

## 5. Blocked

| Item | Blocked by |
|---|---|
| Off-grid operation (LoRa gateway) | antennas for both RA-02 modules |
| Validated camera detection rate | real or controlled fires; enough verdicts |
| Camera model retraining (ML stage 3) | labelled real/false events |
| iOS app | Apple developer account and a Mac |
| More than ~5 nodes | Firebase Spark daily quotas |

## 6. Prioritised next steps

1. Fit RA-02 antennas; finish the LoRa gateway.
2. Reliable power (5 V 2 A or battery + solar) and battery wiring.
3. Add the first fire station on Telegram and test it.
4. Close the RTDB device-key gap (Worker-issued tokens); rotate old keys; delete the old Firebase project.
5. Plan a controlled-burn test with the forest department ([FIELD_TRIAL_PACKAGE.md](FIELD_TRIAL_PACKAGE.md)).

## 7. Commands to continue

```powershell
flutter test ; cd worker ; npm test                         # tests
cd worker ; npx wrangler deploy                             # backend
powershell -ExecutionPolicy Bypass -File tool\deploy_web.ps1
powershell -ExecutionPolicy Bypass -File tool\release_apk.ps1 -Notes "..."
```
