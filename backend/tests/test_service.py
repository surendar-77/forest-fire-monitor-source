"""Service behaviour with Firestore, Auth and FCM mocked out."""

import unittest
from datetime import timedelta
from unittest import mock

from firebase_admin import auth

from forest_fire_backend import service as svc
from forest_fire_backend.service import BackendService, utcnow


def make_service() -> BackendService:
    return BackendService(mock.MagicMock())


class AlertDedupeTest(unittest.TestCase):
    def test_one_alert_per_open_condition(self):
        s = make_service()

        first = s.create_alert_if_new("N1", "FIRE", "HIGH", {})
        second = s.create_alert_if_new("N1", "FIRE", "CRITICAL", {})
        other_type = s.create_alert_if_new("N1", "ENVIRONMENTAL_RISK", "HIGH", {})
        other_node = s.create_alert_if_new("N2", "FIRE", "HIGH", {})

        self.assertIsNotNone(first)
        self.assertIsNone(second)
        self.assertIsNotNone(other_type)
        self.assertIsNotNone(other_node)

    def test_new_alert_is_active_and_unpushed(self):
        s = make_service()
        alert_id = s.create_alert_if_new("N1", "FIRE", "HIGH", {"temperature": 41})
        data = s.open_alerts[alert_id]

        self.assertEqual(data["status"], "ACTIVE")
        self.assertTrue(s._needs_push(data))


class PushWindowTest(unittest.TestCase):
    def test_skips_pushed_old_or_acknowledged_alerts(self):
        s = make_service()
        recent = utcnow() - timedelta(minutes=1)

        self.assertTrue(s._needs_push({"status": "ACTIVE", "detectedAt": recent}))
        self.assertFalse(
            s._needs_push({"status": "ACTIVE", "detectedAt": recent, "pushedAt": recent})
        )
        self.assertFalse(s._needs_push({"status": "ACKNOWLEDGED", "detectedAt": recent}))
        self.assertFalse(
            s._needs_push({"status": "ACTIVE", "detectedAt": utcnow() - timedelta(hours=2)})
        )


class AlertActiveTest(unittest.TestCase):
    def test_writes_only_on_change(self):
        s = make_service()
        devices = s.db.collection.return_value.document.return_value

        s.open_alerts = {"a1": {"deviceId": "N1"}}
        s.refresh_alert_active("N1")
        s.refresh_alert_active("N1")
        self.assertEqual(devices.set.call_count, 1)
        devices.set.assert_called_with({"alertActive": True}, merge=True)

        s.open_alerts = {}
        s.refresh_alert_active("N1")
        self.assertEqual(devices.set.call_count, 2)
        devices.set.assert_called_with({"alertActive": False}, merge=True)


class EscalationTest(unittest.TestCase):
    def setUp(self):
        self.push = mock.patch.object(svc, "push_alert").start()
        self.addCleanup(mock.patch.stopall)

    def test_escalates_to_subscribers_then_admins_then_stops(self):
        s = make_service()
        s.open_alerts = {
            "a1": {
                "deviceId": "N1",
                "status": "ACTIVE",
                "detectedAt": utcnow() - timedelta(minutes=30),
            }
        }

        s.escalate_alerts()
        self.assertEqual(self.push.call_args.kwargs, {"admins_only": False, "escalation": 1})

        s.escalate_alerts()  # too soon after the first escalation
        self.assertEqual(self.push.call_count, 1)

        s.open_alerts["a1"]["escalatedAt"] = utcnow() - timedelta(minutes=11)
        s.escalate_alerts()
        self.assertEqual(self.push.call_args.kwargs, {"admins_only": True, "escalation": 2})

        s.open_alerts["a1"]["escalatedAt"] = utcnow() - timedelta(minutes=11)
        s.escalate_alerts()
        self.assertEqual(self.push.call_count, 2)

    def test_ignores_recent_old_or_acknowledged(self):
        s = make_service()
        s.open_alerts = {
            "new": {"status": "ACTIVE", "detectedAt": utcnow() - timedelta(minutes=2)},
            "acked": {"status": "ACKNOWLEDGED", "detectedAt": utcnow() - timedelta(hours=1)},
            "weeks_old": {"status": "ACTIVE", "detectedAt": utcnow() - timedelta(days=20)},
        }
        s.escalate_alerts()
        self.push.assert_not_called()


class RoleRequestTest(unittest.TestCase):
    def setUp(self):
        self.get_user = mock.patch.object(auth, "get_user").start()
        self.get_by_email = mock.patch.object(auth, "get_user_by_email").start()
        self.set_role = mock.patch.object(svc, "set_role").start()
        self.addCleanup(mock.patch.stopall)
        self.s = make_service()
        self.request_ref = self.s.db.collection.return_value.document.return_value

    def _result(self):
        return self.request_ref.update.call_args.args[0]["status"]

    def test_non_admin_requests_are_rejected(self):
        self.get_user.return_value = mock.Mock(custom_claims={"role": "officer"})
        self.s.apply_role_request("r1", {"requestedBy": "u1", "email": "x@y.org", "role": "admin"})

        self.assertEqual(self._result(), "error")
        self.set_role.assert_not_called()

    def test_admin_can_grant_officer(self):
        self.get_user.return_value = mock.Mock(custom_claims={"role": "admin"})
        target = mock.Mock(uid="u2")
        self.get_by_email.return_value = target

        self.s.apply_role_request("r1", {"requestedBy": "u1", "email": "X@Y.org", "role": "officer"})

        self.get_by_email.assert_called_with("x@y.org")
        self.set_role.assert_called_once_with(self.s.db, target, "officer", changed_by="u1")
        self.assertEqual(self._result(), "done")

    def test_admin_cannot_demote_self(self):
        self.get_user.return_value = mock.Mock(custom_claims={"role": "admin"})
        self.get_by_email.return_value = mock.Mock(uid="u1")

        self.s.apply_role_request("r1", {"requestedBy": "u1", "email": "me@y.org", "role": "viewer"})

        self.assertEqual(self._result(), "error")
        self.set_role.assert_not_called()

    def test_invalid_role_is_rejected(self):
        self.get_user.return_value = mock.Mock(custom_claims={"role": "admin"})
        self.s.apply_role_request("r1", {"requestedBy": "u1", "email": "x@y.org", "role": "god"})
        self.assertEqual(self._result(), "error")


if __name__ == "__main__":
    unittest.main()
