# Forest Fire Monitor audit checklist (2026-10-20)

Evidence and numbers: [PROJECT_STATUS_REPORT.md](PROJECT_STATUS_REPORT.md). Tests at audit time: app 44 passed,
backend 87 passed.

| # | Item | Status |
|---|---|---|
| 1 | Camera AI on the node | Completed and verified (≈2.7 s/frame with ESP-NN) |
| 2 | Fire alert threshold 75%, smoke 50% | Completed and verified (backend tests; node `/alert` filtered) |
| 3 | 2-minute fire confirmation, fire areas only when confirmed | Completed and verified (tests) |
| 4 | Old alerts never silence new fires | Completed and verified (tests; was a real defect) |
| 5 | Offline alerts raised and resolved by `lastSeen` | Completed and verified (tests) |
| 6 | Plain message on every alert | Completed and verified (tests; deployed) |
| 7 | Board health report and sensor-problem alerts | Completed and verified (report read by the backend; tests) |
| 8 | Air at the sensor | Completed and verified (tests; "Clean air" on NODE-01) |
| 9 | MQ-2 fault detection; second MQ-2 not fitted | Completed and verified on hardware |
| 10 | Fire danger model on Indian data | Completed and verified (held-out states and year) |
| 11 | Satellite fires near nodes | Implemented; needs a FIRMS key to run |
| 12 | Push, nearby push, escalation | Completed and verified (test alert received) |
| 13 | Telegram users and fire stations | Implemented; bot connected; no station yet |
| 14 | Sign-up as viewer; roles enforced by rules | Completed and verified (user signed up) |
| 15 | Add sensor (key generation, channel config) | Implemented and unit-tested; not yet used for a second node |
| 16 | Directions | Completed and verified by the user |
| 17 | Graph zoom/pan, CSV, timeline, reports | Completed and tested; released in 1.0.9 |
| 18 | In-app Android updates | Completed and verified (1.0.3 → 1.0.9) |
| 19 | New package name for stores | Completed (1.0.8); old app must be uninstalled once |
| 20 | Secrets out of the repo | Verified: no service-account key, bot token, node key or ThingSpeak key in git history |
| 21 | RTDB device authentication | Known gap: per-node key in firmware; token-based fix pending |
| 22 | LoRa off-grid link | Blocked: no antennas |
| 23 | Field validation of detection | Blocked: no real or controlled fire yet |
| 24 | Commit history without AI co-author lines | Completed (history rewritten 2026-10-20) |
