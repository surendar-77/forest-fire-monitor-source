# Product Requirements — Forest Fire Monitor

> Field prototype. This document describes product intent and acceptance criteria; it is not a certification or
> safety specification.

## 1. Problem

Forest fires in India are mostly detected late: satellites pass a few times a day and see only fires large enough,
watch towers need staff, and single smoke sensors raise false alarms that teach people to ignore them. When an alarm
does arrive, responders rarely know how sure it is, what exactly was seen, where to go, or who is already handling
it. Small forest departments and community groups cannot afford commercial camera towers or paid cloud services.

## 2. Goals

| # | Goal | Measure |
|---|---|---|
| G1 | Detect a fire at the node within seconds | camera result ≤ 3 s per frame; alert on phones ≤ 5 s |
| G2 | Keep false alarms low | 75% camera threshold, 2-minute confirmation; false-alarm share from responder verdicts |
| G3 | Explain every alert | every alert has a written message with confidence, readings and next step |
| G4 | Reach the right people | push to followers, nearby phones, Telegram to users and fire stations |
| G5 | Never fail silently | sensor-problem and offline alerts; backend heartbeat banner |
| G6 | Forecast danger | daily fire-danger level with the riskiest hour, from weather (ML) |
| G7 | Cost nothing to run | free plans only; no credit card needed |

Non-goals: certified fire detection, replacing emergency services, guaranteed delivery without connectivity,
identifying the cause of a fire.

## 3. Users

| User | Need |
|---|---|
| **Forest officer / responder** | know at once, see how sure, navigate to the fire, record what it was |
| **Fire station** | receive serious alerts with the location, without installing an app (Telegram) |
| **Administrator** | add sensors, place them on the map, manage stations and roles, read reports |
| **Viewer (public, students, villagers)** | see sensors, readings and alerts nearby |

## 4. Scope and requirements

### 4.1 Sensor node

| ID | Requirement | Status |
|---|---|---|
| N1 | Camera AI on the node (Fire / Normal / Smoke) | done — ≈2.7 s per frame |
| N2 | Two temperature/humidity zones and smoke sensor | done (one MQ-2 fitted) |
| N3 | Per-second live values; minute summaries for history | done |
| N4 | Direct fire/smoke alerts to the backend | done — ≈2 s to phones |
| N5 | Self-healing Wi-Fi, watchdog, backup networks, serial Wi-Fi commands | done |
| N6 | Board health report (power, Wi-Fi, memory, sensors) every 30 s | done |
| N7 | LoRa link for sites without Wi-Fi | pending — needs antennas |
| N8 | Battery level and charging | ready in firmware; needs wiring |
| N9 | Over-the-air firmware updates | designed, not built |

### 4.2 Backend

| ID | Requirement | Status |
|---|---|---|
| B1 | Risk score, anomaly score against each node's baseline | done |
| B2 | Alert rules with thresholds, repeat merging, 2-minute confirmation | done |
| B3 | Plain message on every alert | done |
| B4 | Sensor-problem and offline alerts that resolve themselves | done |
| B5 | Air at the sensor (clean / smoke / gas) | done |
| B6 | Fire danger (ML) and fire spread estimate | done |
| B7 | NASA satellite fires near each node | done (needs a FIRMS key) |
| B8 | Push, nearby push, Telegram users and fire stations, escalation | done |
| B9 | Admin requests: add sensor with key, test station, set role | done |

### 4.3 App

| ID | Requirement | Status |
|---|---|---|
| A1 | Satellite map with sensors, fire areas, live panel | done |
| A2 | Sensor details: readings, power, Wi-Fi, health | done |
| A3 | Graphs with pinch-zoom and pan; CSV download | done |
| A4 | Alerts: acknowledge, Real fire / False alarm, resolve with outcome | done |
| A5 | Alert timeline, reports with PDF/CSV | done |
| A6 | Directions and navigation | done |
| A7 | Sign-up (viewer), roles, add sensor, fire stations, Telegram link | done |
| A8 | Android APK with in-app updates; web app | done |
| A9 | iOS app | not built (needs an Apple developer account) |
| A10 | Offline maps, Tamil/Hindi, dark mode | proposed |

## 5. Success metrics (current)

- Fire alert reaches phones in about 2 s from the node.
- 44 app tests and 87 backend tests pass.
- Running cost: ₹0 (all free plans).
- False-alarm share: measured from verdicts as they accumulate (no field fires yet).

## 6. Open items

1. LoRa gateway for sites without Wi-Fi (antennas needed).
2. Field validation of the camera thresholds on real or controlled burns.
3. Retrain the camera model from collected verdicts (ML stage 3).
4. Device authentication with backend-issued tokens instead of per-node keys.
5. Reliable power: 5 V 2 A supply or battery + solar.
6. Review and sign-off by a forest department ([docs/FIELD_TRIAL_PACKAGE.md](docs/FIELD_TRIAL_PACKAGE.md)).
