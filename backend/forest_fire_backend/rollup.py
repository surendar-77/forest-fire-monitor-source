"""Hourly rollups for the app's 7-day charts, kept in memory and written once
per node per hour. Writing on every reading would triple the Firestore writes
and use up the Spark plan's 20,000 writes/day much sooner."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class HourBucket:
    node_id: str
    hour: datetime
    count: int = 0
    temperature_sum: float = 0.0
    humidity_sum: float = 0.0
    smoke_max: float | None = None
    fire_probability_max: float | None = None
    risk_score_max: float | None = None

    def add(self, temperature, humidity, smoke, fire_probability, risk_score) -> None:
        self.count += 1
        self.temperature_sum += temperature
        self.humidity_sum += humidity
        self.smoke_max = smoke if self.smoke_max is None else max(self.smoke_max, smoke)
        self.fire_probability_max = (
            fire_probability
            if self.fire_probability_max is None
            else max(self.fire_probability_max, fire_probability)
        )
        self.risk_score_max = (
            risk_score if self.risk_score_max is None else max(self.risk_score_max, risk_score)
        )

    @property
    def doc_id(self) -> str:
        return self.hour.strftime("%Y%m%d%H")


def hour_of(time: datetime) -> datetime:
    return time.replace(minute=0, second=0, microsecond=0)


@dataclass
class HourlyAccumulator:
    buckets: dict[str, HourBucket] = field(default_factory=dict)

    def add(
        self,
        node_id: str,
        time: datetime,
        *,
        temperature: float,
        humidity: float,
        smoke: float,
        fire_probability: float,
        risk_score: float,
    ) -> list[HourBucket]:
        """Adds a reading; returns buckets for earlier hours that are now
        complete and should be written."""
        hour = hour_of(time)
        completed: list[HourBucket] = []

        current = self.buckets.get(node_id)
        if current is not None and current.hour != hour:
            completed.append(current)
            current = None

        if current is None:
            current = HourBucket(node_id=node_id, hour=hour)
            self.buckets[node_id] = current

        current.add(temperature, humidity, smoke, fire_probability, risk_score)
        return completed

    def drain(self) -> list[HourBucket]:
        """All buckets, complete or not, e.g. on shutdown."""
        buckets = [b for b in self.buckets.values() if b.count > 0]
        self.buckets.clear()
        return buckets
