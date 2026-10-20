# Gap Analysis — Forest Fire Early Warning

This document identifies the gaps in how forest fires are detected and reported today, shows which ones Forest
Fire Monitor addresses, and lists what remains open.

## 1. Background

In India most forest fires are small surface fires, lit by people, in the dry months (February–June). They are
found by forest staff on patrol, by villagers, from watch towers, or from satellites. India's Forest Survey of
India (FSI) relays NASA MODIS/VIIRS satellite detections to forest officers, which is free and wide-area but only
a few passes a day, misses small and under-canopy fires, and arrives hours late. Commercial camera towers and
sensor networks exist but cost lakhs per site and need paid cloud services.

## 2. Gaps identified

| # | Gap | Why it matters |
|---|---|---|
| G1 | **Late detection** — satellites pass a few times a day; towers need staff | the first hour decides whether a fire stays small |
| G2 | **False alarms from single sensors** — a smoke sensor reacts to dust, gas and exhaust | people learn to ignore alarms |
| G3 | **No confidence or reason** — an alarm says "fire", not how sure or what was seen | responders cannot judge urgency |
| G4 | **Silent failures** — a dead sensor or camera looks the same as "no fire" | false sense of safety |
| G5 | **No responder workflow** — who saw it, who is going, what it turned out to be | duplicated effort, no learning |
| G6 | **Hard to reach the fire** — the alarm has no route | time lost finding the site |
| G7 | **Fire stations not in the loop** — no app, no integration | slow escalation |
| G8 | **No local danger forecast** — national fire-weather maps are coarse | patrols not planned by risk |
| G9 | **Cost** — towers and paid clouds are out of reach for small divisions and communities | no coverage at all |
| G10 | **Connectivity** — many forest sites have no mobile data or Wi-Fi | a node that cannot send is useless |
| G11 | **No feedback loop** — detectors never learn which alarms were real | accuracy never improves |

## 3. How Forest Fire Monitor addresses them

| Gap | Forest Fire Monitor | Status |
|---|---|---|
| G1 | Camera AI on the node every ≈2.7 s; alert on phones in ≈2 s | ✅ Addressed |
| G2 | 75% camera threshold, 2-minute confirmation, per-node baselines, camera + heat decide smoke vs gas | ✅ Addressed |
| G3 | Every alert carries a plain message with the camera's confidence and readings | ✅ Addressed |
| G4 | Board health every 30 s; camera, sensor, power, battery, Wi-Fi and offline alerts | ✅ Addressed |
| G5 | Acknowledge, Real fire / False alarm, resolve with outcome; timeline; reports | ✅ Addressed |
| G6 | Directions with road route, walk at the end, Google Maps navigation | ✅ Addressed |
| G7 | Telegram alerts with location to fire stations (no app needed) | ✅ Addressed (stations to be added) |
| G8 | ML fire danger per node from weather, with the riskiest hour; terrain factors | ✅ Addressed |
| G9 | ESP32 hardware; Firebase Spark, Cloudflare Workers Free, ThingSpeak, open data | ✅ Addressed |
| G10 | LoRa receiver gateway | ⚠️ Started (receiver built; antennas missing) |
| G11 | Verdicts and outcomes collected; camera-accuracy card suggests thresholds | ⚠️ Started (retraining pending) |

## 4. What remains open

1. **Off-grid connectivity** — finish the LoRa gateway (G10); consider GSM/NB-IoT where there is coverage.
2. **Validated detection** — controlled burns or real fires to measure the camera's true detection and false-alarm
   rates; retrain the model from verdicts (G11).
3. **Power** — solar + battery for unattended sites.
4. **Scale** — more than ~5 nodes needs a paid Firebase plan or fewer reads per node.
5. **Institutional adoption** — review by a forest division ([FIELD_TRIAL_PACKAGE.md](FIELD_TRIAL_PACKAGE.md)).

## 5. Objectives check

| Objective | Status |
|---|---|
| Identify gaps in forest-fire detection | ✅ This document |
| Detect fire early with on-device AI and sensors | ✅ Camera AI, DHT22 ×2, MQ-2 |
| Alert and guide responders with reliable, explained alerts | ✅ Messages, confirmation, push, Telegram, directions |
| Forecast fire danger | ✅ Indian-data ML model |
| Run at no cost | ✅ Free plans only |
| Work without Wi-Fi | ⏳ Pending (LoRa) |
