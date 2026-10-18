"""When a reading should raise an alert."""

from __future__ import annotations

from dataclasses import dataclass

from .thingspeak import SensorReading

AI_FIRE_CONFIDENCE_THRESHOLD = 0.5

#: Alerts that still need someone's attention.
OPEN_STATUSES = ("ACTIVE", "ACKNOWLEDGED")


@dataclass(frozen=True)
class AlertDecision:
    type: str
    severity: str


def decide_alert(reading: SensorReading, risk_level: str) -> AlertDecision | None:
    """Mirrors integrated_monitor.py (CRITICAL risk -> HIGH alert, HIGH risk ->
    MODERATE alert) and also acts on the node's own on-device AI detection
    (ThingSpeak fields 7/8: Fire or Smoke class), escalating when the
    environment agrees."""
    confident = reading.ai_confidence >= AI_FIRE_CONFIDENCE_THRESHOLD
    environment_agrees = risk_level in ("HIGH", "CRITICAL")

    if reading.fire_detected and confident:
        return AlertDecision("FIRE", "CRITICAL" if environment_agrees else "HIGH")

    if reading.smoke_detected and confident:
        return AlertDecision("SMOKE", "HIGH" if environment_agrees else "MODERATE")

    if risk_level == "CRITICAL":
        return AlertDecision("ENVIRONMENTAL_RISK", "HIGH")

    if risk_level == "HIGH":
        return AlertDecision("ENVIRONMENTAL_RISK", "MODERATE")

    return None
