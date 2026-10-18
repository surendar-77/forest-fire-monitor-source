"""Environmental fire-risk model.

Same rules as ``calculate_risk`` in the original ThingSpeak bridge: each
sensor contributes 0-2 points and the total is normalised to a 12-point
scale when secondary sensors are missing. The app shows risk out of 100, so
``score`` is the 12-point total scaled to 0-100.
"""

from __future__ import annotations

import os
from dataclasses import dataclass


def _env_float(name: str, default: float) -> float:
    return float(os.getenv(name, str(default)))


@dataclass(frozen=True)
class Thresholds:
    temp_warn: float = _env_float("RISK_TEMP_WARN", 35)
    temp_high: float = _env_float("RISK_TEMP_HIGH", 45)
    humidity_warn: float = _env_float("RISK_HUMIDITY_WARN", 30)
    humidity_high: float = _env_float("RISK_HUMIDITY_HIGH", 20)
    mq2_warn: float = _env_float("RISK_MQ2_WARN", 400)
    mq2_high: float = _env_float("RISK_MQ2_HIGH", 800)


DEFAULT_THRESHOLDS = Thresholds()


@dataclass(frozen=True)
class Risk:
    points: int  # 0-12, as the original bridge reported
    score: int  # 0-100, what the app displays
    level: str  # LOW / MODERATE / HIGH / CRITICAL


def _temp_points(value, t: Thresholds) -> int:
    if value is None:
        return 0
    return 2 if value >= t.temp_high else (1 if value >= t.temp_warn else 0)


def _humidity_points(value, t: Thresholds) -> int:
    if value is None:
        return 0
    return 2 if value <= t.humidity_high else (1 if value <= t.humidity_warn else 0)


def _mq2_points(value, t: Thresholds) -> int:
    if value is None:
        return 0
    return 2 if value >= t.mq2_high else (1 if value >= t.mq2_warn else 0)


def level_for_points(points: int) -> str:
    if points <= 2:
        return "LOW"
    if points <= 5:
        return "MODERATE"
    if points <= 8:
        return "HIGH"
    return "CRITICAL"


def calculate_risk(
    temperature,
    humidity,
    mq2_1,
    mq2_2=None,
    temperature2=None,
    humidity2=None,
    thresholds: Thresholds = DEFAULT_THRESHOLDS,
) -> Risk:
    score = (
        _temp_points(temperature, thresholds)
        + _humidity_points(humidity, thresholds)
        + _mq2_points(mq2_1, thresholds)
    )
    max_points = 6

    if temperature2 is not None:
        score += _temp_points(temperature2, thresholds)
        max_points += 2
    if humidity2 is not None:
        score += _humidity_points(humidity2, thresholds)
        max_points += 2
    if mq2_2 is not None:
        score += _mq2_points(mq2_2, thresholds)
        max_points += 2

    points = int(round(score / max_points * 12)) if max_points < 12 else score

    return Risk(points=points, score=round(points / 12 * 100), level=level_for_points(points))
