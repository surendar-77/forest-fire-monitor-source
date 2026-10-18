"""Unit tests for the pure logic. Run from backend/:  python -m unittest"""

import unittest
from datetime import datetime, timezone

from forest_fire_backend.alert_rules import decide_alert
from forest_fire_backend.risk import calculate_risk, level_for_points
from forest_fire_backend.rollup import HourlyAccumulator
from forest_fire_backend.thingspeak import parse_feed

NOW = datetime(2026, 10, 18, 12, 0, tzinfo=timezone.utc)

FEED = {
    "created_at": "2026-10-18T11:59:30Z",
    "entry_id": 941,
    "field1": "31.5",
    "field2": "48",
    "field3": "30.9",
    "field4": "",
    "field5": "420",
    "field6": None,
    "field7": "0",
    "field8": "87",
}


class RiskTest(unittest.TestCase):
    # Same cases as the original bridge's calculate_risk().

    def test_calm_is_low(self):
        risk = calculate_risk(28, 60, 150, 140, 27, 62)
        self.assertEqual((risk.points, risk.score, risk.level), (0, 0, "LOW"))

    def test_all_high_is_critical(self):
        risk = calculate_risk(46, 15, 900, 850, 47, 18)
        self.assertEqual((risk.points, risk.score, risk.level), (12, 100, "CRITICAL"))

    def test_primary_only_is_normalised(self):
        risk = calculate_risk(36, 25, 500)
        self.assertEqual((risk.points, risk.score, risk.level), (6, 50, "HIGH"))

    def test_rounds_half_to_even_like_original(self):
        self.assertEqual(calculate_risk(36, 60, 100, 100).points, 2)

    def test_missing_primary_counts_zero(self):
        risk = calculate_risk(None, None, 900)
        self.assertEqual((risk.points, risk.level), (4, "MODERATE"))

    def test_level_boundaries(self):
        self.assertEqual(
            [level_for_points(p) for p in (2, 3, 5, 6, 8, 9)],
            ["LOW", "MODERATE", "MODERATE", "HIGH", "HIGH", "CRITICAL"],
        )


class FeedTest(unittest.TestCase):
    def test_parses_fields(self):
        r = parse_feed(FEED, NOW, 120)
        self.assertEqual(r.temperature, 31.5)
        self.assertEqual(r.humidity2, None)
        self.assertEqual(r.mq2_2, 0.0)
        self.assertEqual(r.ai_class, "Fire")  # field7 "0" is the Fire class
        self.assertAlmostEqual(r.ai_confidence, 0.87)
        self.assertEqual(r.entry_id, 941)
        self.assertEqual(r.age_seconds, 30)
        self.assertFalse(r.is_stale)

    def test_old_entries_are_stale(self):
        r = parse_feed({**FEED, "created_at": "2026-10-18T11:55:00Z"}, NOW, 120)
        self.assertTrue(r.is_stale)

    def test_silent_dht_still_parses(self):
        r = parse_feed({**FEED, "field1": "", "field2": ""}, NOW, 120)
        self.assertIsNone(r.temperature)
        self.assertEqual(r.mq2_1, 420)

    def test_rejects_bad_readings(self):
        for bad in (
            {"field1": "", "field2": "", "field5": ""},
            {"field2": "140"},
            {"field1": "99"},
            {"created_at": "2026-10-18T12:05:00Z"},
        ):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                parse_feed({**FEED, **bad}, NOW, 120)


class AlertRulesTest(unittest.TestCase):
    def test_confident_normal_raises_nothing(self):
        r = parse_feed({**FEED, "field7": "1", "field8": "0.95"}, NOW, 120)
        self.assertEqual(r.ai_class, "Normal")
        self.assertIsNone(decide_alert(r, "LOW"))

    def test_smoke_class(self):
        r = parse_feed({**FEED, "field7": "2", "field8": "81"}, NOW, 120)
        self.assertEqual((decide_alert(r, "LOW").type, decide_alert(r, "LOW").severity), ("SMOKE", "MODERATE"))
        self.assertEqual(decide_alert(r, "CRITICAL").severity, "HIGH")

    def test_ai_detection(self):
        r = parse_feed({**FEED, "field7": "0", "field8": "0.9"}, NOW, 120)
        self.assertEqual(decide_alert(r, "LOW").severity, "HIGH")
        self.assertEqual(decide_alert(r, "HIGH").severity, "CRITICAL")
        self.assertEqual(decide_alert(r, "HIGH").type, "FIRE")

    def test_environmental_risk(self):
        r = parse_feed({**FEED, "field7": "0", "field8": "30"}, NOW, 120)
        self.assertIsNone(decide_alert(r, "LOW"))
        self.assertEqual(decide_alert(r, "CRITICAL").severity, "HIGH")
        self.assertEqual(decide_alert(r, "HIGH").severity, "MODERATE")


class RollupTest(unittest.TestCase):
    def test_bucket_completes_when_hour_changes(self):
        acc = HourlyAccumulator()
        values = dict(humidity=50, smoke=300, fire_probability=0, risk_score=10)

        self.assertEqual(acc.add("N1", NOW.replace(minute=5), temperature=30, **values), [])
        self.assertEqual(
            acc.add("N1", NOW.replace(minute=40), temperature=34, **{**values, "smoke": 700}), []
        )

        done = acc.add("N1", NOW.replace(hour=13, minute=1), temperature=29, **values)

        self.assertEqual(len(done), 1)
        bucket = done[0]
        self.assertEqual(bucket.doc_id, "2026101812")
        self.assertEqual(bucket.count, 2)
        self.assertEqual(bucket.temperature_sum, 64)
        self.assertEqual(bucket.smoke_max, 700)

    def test_nodes_are_independent_and_drain_returns_partials(self):
        acc = HourlyAccumulator()
        values = dict(temperature=30, humidity=50, smoke=1, fire_probability=0, risk_score=0)
        acc.add("N1", NOW, **values)
        acc.add("N2", NOW, **values)

        self.assertEqual(sorted(b.node_id for b in acc.drain()), ["N1", "N2"])
        self.assertEqual(acc.drain(), [])


if __name__ == "__main__":
    unittest.main()
