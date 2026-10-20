# Forest Fire Monitor — field trial package (for a forest division)

This package is for a Range or Divisional Forest Officer reviewing the system before a field trial. It is a
prototype; it supports patrols and does not replace them.

## 1. What the system does

- A node with a camera, two temperature/humidity sensors and a smoke sensor watches one spot of forest.
- When the camera is at least 75% sure it sees flames, phones ring within seconds with a written message; after
  2 minutes of continuous fire the alert becomes critical and fire stations are told on Telegram with the location.
- Each node reports its own health; a dead camera, sensor, low battery or lost power becomes an alert.
- A daily fire-danger level (Low / Medium / High) and the riskiest hour come from weather and forest type.

## 2. What we ask the reviewer to confirm

| # | Question | Default in the system |
|---|---|---|
| 1 | Who should get fire alerts (staff, fire stations, villagers)? | everyone following the sensor; stations within 25 km |
| 2 | Is 75% camera confidence the right point to alert? | 75% fire, 50% smoke |
| 3 | Is 2 minutes the right confirmation time before "critical"? | 2 minutes |
| 4 | What should a responder do on a smoke-only alert? | check the area, watch for flames |
| 5 | Which forest type applies at each site? | set per sensor (pine, bamboo, dry deciduous, …) |
| 6 | How fast must an alert be acknowledged before escalation? | 10 minutes, then administrators |
| 7 | Is Telegram acceptable for fire stations, or is SMS required? | Telegram |

## 3. Trial plan (proposal)

1. **Sites:** 2–3 nodes at high-risk spots with Wi-Fi or a LoRa gateway; mains or solar power.
2. **Controlled burns:** with permission, small supervised fires at known distances (5, 10, 20 m) and times of day,
   to measure detection time and confidence.
3. **Daily use:** staff mark every alert *Real fire* or *False alarm*; the accuracy card and Reports measure the
   false-alarm share and response times.
4. **Review after 4 weeks:** thresholds, coverage per node, power and connectivity problems, staff feedback.

## 4. What the trial will produce

- Detection time and camera confidence per controlled burn.
- False-alarm share and typical time to acknowledge/resolve (Reports → PDF).
- A labelled set of real and false events to retrain the camera model.

## 5. Limits to know before starting

- Only fires visible to the camera are detected by it; smoke and heat sensors cover a few metres.
- Without Wi-Fi or a working LoRa link, a node cannot alert.
- Free cloud plans limit the system to about 5 nodes.
- The fire-danger level rates conditions; most fires are lit by people.
