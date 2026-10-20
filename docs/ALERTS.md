# Alerts: rules, messages and workflow

All alert decisions are made by the Cloudflare Worker (`worker/src/`), except fire/smoke alerts the node sends
itself, which the Worker re-checks. Every alert document lives in Firestore `alerts/{id}`.

## Types and thresholds

| Type | Severity | Raised when | Source |
|---|---|---|---|
| `FIRE` | HIGH, CRITICAL if the sensors agree or fire danger is high | camera Fire ≥ **75%** | `alertRules.ts`, node `/alert` |
| `SMOKE` | MODERATE, HIGH if the sensors agree or danger is high | camera Smoke ≥ **50%** | same |
| `SENSOR_ANOMALY` | HIGH, CRITICAL on a high-danger day | anomaly level LIKELY (smoke/heat far from this node's normal) | `anomaly.ts` |
| `SATELLITE_HOTSPOT` | HIGH, CRITICAL on a high-danger day | NASA FIRMS VIIRS detection near the node (not low confidence) | `firms.ts` |
| `NODE_OFFLINE` | HIGH | no data for 10 min | `index.ts` node health |
| `ENVIRONMENTAL_RISK` | from the node | hot/dry/smoky conditions on the node | node `/alert` |
| `CAMERA_OFFLINE` | MODERATE | no camera photo for 10 min | `health.ts` |
| `SENSOR_FAULT` | MODERATE | a DHT22 not reading or an MQ-2 faulty for 10 min | `health.ts` |
| `POWER_PROBLEM` | MODERATE | the board restarted after a brownout (once per restart) | `health.ts` |
| `LOW_BATTERY` | MODERATE ≤ 20%, HIGH ≤ 10% | for 5 min | `health.ts` |
| `WEAK_WIFI` | LOW | signal below −80 dBm for 15 min | `health.ts` |
| `BOARD_HOT` | MODERATE | chip ≥ 80 °C for 10 min | `health.ts` |

Sensor-problem alerts and offline alerts **resolve themselves** when the problem clears; they are never escalated
and never sent to fire stations.

## Repeats and confirmation

* A new fire/smoke/anomaly detection is merged into an open alert of the same type that is recent
  (ACTIVE within 10 min, or ACKNOWLEDGED within 30 min); an old unresolved alert never silences a new fire.
* Each repeat extends the streak. Reports more than 150 s apart break it. A fire seen **2 minutes without a
  break** gets `confirmedAt`, becomes CRITICAL and sends a second, critical notification; only confirmed fires
  draw a fire area on the map.

## Messages

Every alert has a `message` (`worker/src/alertMessages.ts`): what was seen, how sure the camera is, the
readings, whether the sensors agree, whether fire danger is high, and what to do. Example:

> The camera at Forest Monitoring Node 01 sees flames (92% sure). Readings: 41.2 °C, 18% humidity, smoke
> level 1450. The smoke and heat sensors agree. Check the area now and call the fire service if it is confirmed.

Confirmation prefixes: *"Confirmed: the camera has seen this fire continuously for over 2 minutes. Send help now."*

## Who is told

| Channel | Who | Which alerts |
|---|---|---|
| Push (FCM) | users following the sensor (all sensors by default) | all |
| Push, nearby | phones that opted in, within 10 km | HIGH / CRITICAL, not sensor problems |
| Telegram, users | users who connected Telegram (Settings → Connect Telegram) | same as their push |
| Telegram, fire stations | stations within 25 km, or all stations if none is that close | HIGH / CRITICAL fire alerts, not sensor problems |
| Escalation | re-push after 10 min unacknowledged; then admins only | ACTIVE alerts up to 6 h old, not sensor problems |

Telegram needs the Worker secret `TELEGRAM_BOT_TOKEN`. People who send `/start` to the bot appear in the app
for an admin to pick as a station; `/start CODE` links an app user; `/stop` unlinks.

## Responder workflow

ACTIVE → **Acknowledge** (ACKNOWLEDGED) → **Resolve** with an outcome (confirmed fire, false alarm, controlled
burn, test/drill). On open camera alerts: **Real fire** (stays open, marked handled) or **False alarm**
(resolved as a false alarm). The rules allow these transitions for officers and admins only, stamped with their
uid and the server time.

The **camera-accuracy card** compares verdicts with the camera confidence and suggests a threshold when one
would have kept every real fire and dropped every false alarm. The **timeline** and **Reports** screen show
each step with times (see docs/DATA.md for the CSV columns).
