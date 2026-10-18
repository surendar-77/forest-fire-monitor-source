"""Reading the latest entry of a ThingSpeak channel.

Field layout (per channel):
  1 Temperature 1 (°C)   2 Humidity 1 (%)
  3 Temperature 2 (°C)   4 Humidity 2 (%)
  5 MQ-2 sensor 1        6 MQ-2 sensor 2
  7 AI class: 0 Fire, 1 Normal, 2 Smoke (as ForestFire_S3.ino sends it)
  8 AI confidence of that class (0-1 or 0-100)
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

import requests

AI_CLASSES = ("Fire", "Normal", "Smoke")


@dataclass(frozen=True)
class SensorReading:
    temperature: float
    humidity: float
    temperature2: float | None
    humidity2: float | None
    mq2_1: float
    mq2_2: float
    ai_class: str | None  # camera model prediction, None before the first
    fire_detected: bool
    smoke_detected: bool
    ai_confidence: float  # 0-1, of ai_class
    timestamp: datetime
    entry_id: int | None
    age_seconds: float
    is_stale: bool


def _field(feed: dict, number: int) -> float | None:
    value = feed.get(f"field{number}")
    if value is None or str(value).strip() == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def parse_feed(feed: dict, now: datetime, max_age_seconds: float) -> SensorReading:
    temperature = _field(feed, 1)
    humidity = _field(feed, 2)

    if temperature is None or humidity is None:
        raise ValueError("Primary sensor (temperature/humidity) reading is missing")

    created = feed.get("created_at")
    if not created:
        raise ValueError("ThingSpeak timestamp is missing")

    timestamp = datetime.fromisoformat(str(created).replace("Z", "+00:00")).astimezone(
        timezone.utc
    )
    age_seconds = (now - timestamp).total_seconds()

    if age_seconds < -30:
        raise ValueError("ThingSpeak timestamp is unexpectedly in the future")
    if not 0 <= humidity <= 100:
        raise ValueError(f"Invalid primary humidity reading: {humidity}")
    if not -40 <= temperature <= 85:
        raise ValueError(f"Invalid primary temperature reading: {temperature}")

    confidence = _field(feed, 8) or 0.0
    if 1 < confidence <= 100:
        confidence /= 100.0

    entry_id = feed.get("entry_id")

    class_index = _field(feed, 7)
    ai_class = (
        AI_CLASSES[int(class_index)]
        if class_index is not None and class_index.is_integer() and 0 <= class_index < 3
        else None
    )

    return SensorReading(
        temperature=temperature,
        humidity=humidity,
        temperature2=_field(feed, 3),
        humidity2=_field(feed, 4),
        mq2_1=_field(feed, 5) or 0.0,
        mq2_2=_field(feed, 6) or 0.0,
        ai_class=ai_class,
        fire_detected=ai_class == "Fire",
        smoke_detected=ai_class == "Smoke",
        ai_confidence=confidence,
        timestamp=timestamp,
        entry_id=entry_id if isinstance(entry_id, int) else None,
        age_seconds=max(0.0, age_seconds),
        is_stale=age_seconds > max_age_seconds,
    )


def fetch_last_feed(channel_id: str, read_api_key: str | None = None) -> dict:
    params = {"api_key": read_api_key} if read_api_key else {}
    response = requests.get(
        f"https://api.thingspeak.com/channels/{channel_id}/feeds/last.json",
        params=params,
        timeout=10,
    )
    response.raise_for_status()
    body = response.json()

    if not isinstance(body, dict):
        raise ValueError(f"ThingSpeak channel {channel_id} has no data or is private")
    return body
