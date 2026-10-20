# Sensor node hardware and firmware

**The firmware is kept outside this repository** because it contains secrets (Wi-Fi passwords, the node key,
the ThingSpeak write key). Never commit `ForestFire_S3.ino` or paste those values into issues or docs.

## Boards

| Part | Role |
|---|---|
| ESP32-S3 (16 MB flash, OPI PSRAM) | main node: sensors, camera AI, Wi-Fi, cloud uploads, local dashboard |
| ESP32-CAM (AI-Thinker) | camera only: joins the S3's own Wi-Fi `FireDetector`, posts a 240×240 JPEG every 3 s to `http://192.168.4.1/upload` |
| DHT22 × 2 | temperature / humidity, zones 1 and 2 |
| MQ-2 | smoke / combustible gas (one fitted) |
| RA-02 (SX1278, 433 MHz) | LoRa backup link to a receiver gateway, 10 dBm (the licence-free limit for 433 MHz in India) |
| ESP32 DevKit V1 + RA-02 | LoRa receiver gateway (`LoRa_Receiver.ino`): forwards packets to `/lora/data` and link reports to `/lora` |

## Pins (ESP32-S3)

| Signal | GPIO |
|---|---|
| DHT22 zone 1 / zone 2 | 4 / 5 |
| MQ-2 sensor 1 / sensor 2 (AO) | 1 / 3 |
| LoRa SCK / MISO / MOSI / SS / RST / DIO0 | 12 / 13 / 11 / 10 / 14 / 2 |
| Battery divider / charger CHRG (optional) | set `BATTERY_PIN` / `CHARGE_PIN` (default −1 = not fitted) |

Set `MQ2_INSTALLED false` when only one MQ-2 is fitted: an unconnected ADC pin floats and reads random values.

## Build and flash

* Arduino IDE 2 / arduino-cli, ESP32 core **3.3.11** (built-in esp-tflite-micro + ESP-NN).
* FQBN: `esp32:esp32:esp32s3:CDCOnBoot=cdc,FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,PSRAM=opi`
* Partition table: two 3 MB app slots (`app0`, `app1`), 9.9 MB FFat, coredump.
  **Never erase flash or change the partition scheme** — FFat holds `model.tflite`.
* Flash only the app at `0x10000`:

```powershell
arduino-cli compile --fqbn "<FQBN above>" --output-dir build .
esptool --chip esp32s3 --port COM10 --baud 115200 --before default-reset --after hard-reset write-flash 0x10000 build/ForestFire_S3.ino.bin
```

`--baud 115200` is reliable where 921600 fails. If Windows shows "Unknown USB Device", replug, try another cable
or port, or hold **BOOT**, tap **RESET**, release **BOOT** (download mode). Close the Arduino Serial Monitor
first: only one program can hold the port.

## What the firmware does

| Task | Rate |
|---|---|
| MQ-2 read (16-sample average, burst-noise / swing / stuck fault detection) | 1 s |
| DHT22 read + LoRa packet | 2.5 s |
| Camera AI on each new photo (Fire / Normal / Smoke) | ≈2.7 s per frame |
| Live values → RTDB `live/{node}` | 1 s |
| Board health → RTDB `health/{node}` | 30 s |
| ThingSpeak summary (worst value of each sensor in the minute) | 60 s |
| Fire/smoke alert → Worker `/alert` | immediately, ≥ 60 s apart per type |

Smoke is scored as a rise above each MQ-2's learned clean-air baseline (+300 warn, +700 high counts) after the
heater warm-up, because raw levels differ widely between modules.

## Wi-Fi and self-healing

* Networks: the main network, a backup network, and one saved from the serial console. A failed join rotates
  to the next; a network chosen with `wifi use` is retried for 2 minutes first.
* No cloud upload for 5 min → rejoin; for 20 min → restart. Task watchdog 30 s on the loop and cloud tasks.
* The S3 also runs its own access point `FireDetector` (camera + local dashboard at `http://192.168.4.1`).
* ESP32 radios are **2.4 GHz only**. A Windows hotspot works only while the PC's own Wi-Fi is on 2.4 GHz.

Serial commands (USB, 115200 baud, newline):

```
wifi status | wifi scan | wifi use pg|hotspot|custom | wifi set "Name" password | wifi forget | wifi restart
```

`esp-wifi.ps1` sends them from PowerShell: `powershell -ExecutionPolicy Bypass -File esp-wifi.ps1 status`.

## Board health report

Every 30 s: uptime, restart reason (power-on, brownout, watchdog, crash, …), start count, firmware version,
optional battery %/voltage/charging, Wi-Fi name/signal/IP/channel, devices on `FireDetector`, free heap/PSRAM,
chip temperature, upload success, camera photo age and AI time, DHT/MQ status, LoRa and ThingSpeak status.
The app shows it on the sensor details page; the Worker turns problems into alerts (docs/ALERTS.md).

## Battery monitoring (optional)

Battery + → 100 kΩ → ADC pin → 100 kΩ → GND (`BATTERY_DIVIDER 2.0`), and a TP4056 `CHRG` pin (low while
charging) to a free GPIO. Set `BATTERY_PIN` / `CHARGE_PIN` and reflash; the app then shows battery and charging.

## Security note

RTDB writes from the node are authorised by comparing a per-node key (`deviceKeys/{node}`) in the rules. Anyone
who extracts the key from a board can write that node's live values. The planned fix is Worker-minted custom
tokens per device. Add a sensor from the app (Settings → Add a sensor) to get a fresh random key.
