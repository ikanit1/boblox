"""Synthetic exports test review policy, not real performance."""
import copy
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("performance_validation", Path(__file__).parents[1] / "validate_performance.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PerformanceValidationTests(unittest.TestCase):
    def setUp(self):
        self.fingerprint = "a" * 64
        self.capture = {"FormatVersion": 1, "SourceFingerprint": self.fingerprint,
                        "Context": "StudioClient", "DurationSeconds": 120,
                        "IntervalMs": {"P50": 16, "P95": 20, "P99": 32, "WindowCount": 6000},
                        "Checkpoints": [{"Phase": "Rule", "RuleId": "MeteorRain", "Players": 12, "ActivePlayers": 12}],
                        "MemoryMb": {"Count": 120}, "DataSendKbps": {"Count": 120},
                        "DataReceiveKbps": {"Count": 120}}
        self.context = {"DeviceModel": "SYNTHETIC_FIXTURE", "GraphicsQuality": "5",
                        "NetworkDescription": "SYNTHETIC_FIXTURE", "Scenario": "meteors",
                        "ActualClients": 12, "SourcesComparedWithCandidate": True, "TargetFPS": 30}
        for metric in ("MemoryMb", "DataSendKbps", "DataReceiveKbps"):
            self.capture[metric].update(P50=10, P95=12, P99=15, LifetimeMin=8, LifetimeMean=11, LifetimeMax=20)

    def assess(self):
        return MODULE.assess(self.capture, self.context, self.fingerprint)

    def test_missing_never_passes(self):
        result = MODULE.assess(None, {}, self.fingerprint)
        self.assertEqual(result["status"], "Missing")
        self.assertFalse(result["nativeAcceptance"])

    def test_complete_is_review_not_acceptance(self):
        result = self.assess()
        self.assertEqual(result["status"], "ReadyForReview")
        self.assertFalse(result["nativeAcceptance"])

    def test_identity_and_export_error_fail(self):
        for key, value in (("SourceFingerprint", "b" * 64), ("Error", "ExportSizeLimit"), ("FormatVersion", 2)):
            with self.subTest(key=key):
                original = copy.deepcopy(self.capture)
                self.capture[key] = value
                self.assertEqual(self.assess()["status"], "Invalid")
                self.capture = original

    def test_operator_context_is_required(self):
        self.context = {}
        self.assertNotEqual(self.assess()["status"], "ReadyForReview")

    def test_bad_percentiles_are_rejected(self):
        for value in (float("nan"), float("inf"), -1, True, "20"):
            self.capture["IntervalMs"]["P95"] = value
            self.assertEqual(self.assess()["status"], "Invalid")

    def test_order_and_budget(self):
        self.capture["IntervalMs"]["P95"] = 12
        self.assertEqual(self.assess()["status"], "Invalid")
        self.capture["IntervalMs"].update(P95=40, P99=50)
        self.assertEqual(self.assess()["status"], "NeedsInvestigation")

    def test_wrong_rule_and_capacity_missing(self):
        self.context["Scenario"] = "reactor"
        self.assertIn("requested_rule_not_observed", self.assess()["missing"])
        self.context.update(Scenario="full_arena", ActualClients=2)
        self.assertIn("12_actual_clients", self.assess()["missing"])

    def test_lobby_players_do_not_prove_arena_capacity(self):
        self.context["Scenario"] = "full_arena"
        self.capture["Checkpoints"][0]["ActivePlayers"] = 1
        self.assertIn("12_players_in_active_arena", self.assess()["missing"])

    def test_phone_and_soak_are_separate(self):
        self.context["Scenario"] = "phone_soak"
        self.assertIn("PhysicalDevice", self.assess()["missing"])
        self.assertIn("DurationSeconds_at_least_1800", self.assess()["missing"])

    def test_unknown_metrics_do_not_become_zero(self):
        self.capture.pop("MemoryMb")
        self.assertIn("MemoryMb", self.assess()["missing"])

    def test_incomplete_or_corrupt_metric_summaries_are_not_ready(self):
        self.capture["MemoryMb"] = {"Count": 120}
        self.assertIn("MemoryMb_summary", self.assess()["missing"])
        self.capture["MemoryMb"].update(P50=-1, P95=float("nan"), P99=float("inf"),
                                        LifetimeMin=0, LifetimeMean="missing", LifetimeMax=100)
        self.assertEqual(self.assess()["status"], "Invalid")

    def test_server_interval_is_not_client_fps(self):
        self.capture["Context"] = "StudioServer"
        self.capture["IntervalMs"].update(P50=40, P95=50, P99=60)
        self.assertEqual(self.assess()["budgetFindings"], [])

    def test_malformed_checkpoint_is_invalid(self):
        self.capture["Checkpoints"] = ["bad"]
        self.assertEqual(self.assess()["status"], "Invalid")


if __name__ == "__main__":
    unittest.main()
