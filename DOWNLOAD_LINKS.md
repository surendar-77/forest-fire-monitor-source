# Forest Fire Monitor · Download links

Everything that is **not** in this repository, where to get it, and where to put it.

> **You do not need any of this to use the app.** Install the APK or open the web app and create an account.
> These links are for building, deploying or retraining.

---

## 1. The app

| What | Link |
|---|---|
| Android app (latest APK, release notes) | <https://github.com/surendar-77/forest-fire-monitor/releases/latest> |
| Web app | <https://forest-fire-3d2f0.web.app> |
| In-app update feed | <https://forest-fire-backend.forest-fire-worker.workers.dev/apk/version.json> |
| Privacy policy | <https://forest-fire-3d2f0.web.app/privacy.html> |
| Source code (private) | <https://github.com/surendar-77/forest-fire-monitor-source> |

---

## 2. Services (all free plans)

| Service | Used for | Sign-up |
|---|---|---|
| **Firebase** (Spark) | sign-in, Firestore, Realtime Database, push, web hosting | <https://console.firebase.google.com> |
| **Cloudflare Workers** (Free) | backend, APK hosting | <https://dash.cloudflare.com/sign-up> |
| **ThingSpeak** (free) | minute history per sensor | <https://thingspeak.mathworks.com> |
| **Telegram** bot | alerts to users and fire stations | @BotFather in Telegram |
| **NASA FIRMS** map key | satellite fires near sensors (optional) | <https://firms.modaps.eosdis.nasa.gov/api/map_key/> |
| **Open-Meteo** | weather for fire danger (no key) | <https://open-meteo.com> |
| **OpenRouteService** | road routing for production (free key; the app uses public OSRM until then) | <https://openrouteservice.org/dev/#/signup> |

---

## 3. Data for the fire-danger model

| Dataset | Used for | Put it in | Download | Licence |
|---|---|---|---|---|
| **NASA FIRMS VIIRS S-NPP** yearly country files, India 2022–2024 | fire labels | `ml/data/india/viirs_{year}_India.csv` | `https://firms.modaps.eosdis.nasa.gov/data/country/viirs-snpp/{year}/viirs-snpp_{year}_India.csv` | NASA open data |
| **ERA5** via the Open-Meteo archive | weather features | fetched by `ml/india_dataset.py` | <https://open-meteo.com/en/docs/historical-weather-api> | CC BY 4.0 |
| UCI **Algerian Forest Fires** (previous model) | comparison only | `ml/data/` | <https://archive.ics.uci.edu/dataset/547/algerian+forest+fires+dataset> | CC BY 4.0 |

Training commands: [ml/README.md](ml/README.md).

---

## 4. Software

| What | Needed for | Link |
|---|---|---|
| **Flutter 3.47** (Dart 3.13) | the app | <https://docs.flutter.dev/get-started/install> |
| Android SDK + NDK 28.2.13676358 | Android builds | Android Studio / `sdkmanager "ndk/28.2.13676358"` |
| **Node.js 22** | backend (Wrangler), rules tests | <https://nodejs.org> |
| Firebase CLI | rules, hosting | `npm install -g firebase-tools` |
| Java 11+ | security-rules tests (emulator) | <https://adoptium.net> |
| **Arduino IDE 2** + ESP32 core 3.3.11 | node firmware | <https://www.arduino.cc/en/software> · Boards Manager "esp32" |
| Python 3.11 | ML training, Python backend | <https://www.python.org/downloads/release/python-3119/> |
| GitHub CLI | releases | <https://cli.github.com> |

---

## 5. Things with no download link

| Left out | What it is | If you need it |
|---|---|---|
| Node firmware (`ForestFire_S3.ino`, `ESP32CAM_Uploader.ino`, `LoRa_Receiver.ino`) | contains secrets | keep it with the hardware; see [docs/HARDWARE.md](docs/HARDWARE.md) |
| `model.tflite` on the node's FFat | camera classifier | on the board; never erase flash |
| Service-account key, keystore, Telegram token | secrets | `C:\secure\` and Worker secrets ([docs/DEPLOYMENT.md](docs/DEPLOYMENT.md#7-secrets-checklist)) |
| `worker/public/apk/`, `releases/`, `build/` | generated release files | re-create with `tool\release_apk.ps1` |
