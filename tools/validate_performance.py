"""Review exported diagnostic data; never substitute fixtures for device acceptance."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

SCENARIOS = {"full_arena", "meteors", "reactor", "respawn_results", "collection", "repeated_runs", "phone_soak"}


def finite(value):
    return isinstance(value, (float, int)) and not isinstance(value, bool) and math.isfinite(value)


def assess(capture: dict | None, context: dict, fingerprint: str) -> dict:
    missing, invalid, budgets = [], [], []
    result = {"status": "Missing", "nativeAcceptance": False,
              "sourceAttestation": "operator_statement_requires_review",
              "missing": missing, "invalid": invalid, "budgetFindings": budgets}
    if not isinstance(capture, dict):
        missing.append("capture")
        return result
    if not isinstance(context, dict):
        context = {}
    if capture.get("FormatVersion") != 1 or capture.get("Error"):
        invalid.append("capture_format_or_export_error")
    if capture.get("SourceFingerprint") != fingerprint or len(fingerprint) != 64:
        invalid.append("candidate_identity_mismatch")
    if capture.get("Context") not in {"StudioClient", "StudioServer"}:
        invalid.append("unknown_capture_context")
    for field in ("DeviceModel", "GraphicsQuality", "NetworkDescription", "Scenario"):
        if not isinstance(context.get(field), str) or not context[field].strip():
            missing.append(field)
    if context.get("Scenario") not in SCENARIOS:
        invalid.append("unknown_scenario")
    clients = context.get("ActualClients")
    if not isinstance(clients, int) or isinstance(clients, bool) or not 1 <= clients <= 12:
        missing.append("ActualClients_1_to_12")
    if context.get("SourcesComparedWithCandidate") is not True:
        missing.append("SourcesComparedWithCandidate")
    duration = capture.get("DurationSeconds")
    required = 1800 if context.get("Scenario") == "phone_soak" else 120
    if not finite(duration) or duration < required:
        missing.append(f"DurationSeconds_at_least_{required}")
    if context.get("Scenario") == "phone_soak" and context.get("PhysicalDevice") is not True:
        missing.append("PhysicalDevice")
    if context.get("Scenario") == "repeated_runs":
        runs = context.get("CompletedRuns")
        if not isinstance(runs, int) or isinstance(runs, bool) or runs < 10:
            missing.append("CompletedRuns_at_least_10")
    frames = capture.get("IntervalMs", {})
    if not isinstance(frames, dict):
        frames = {}
    percentiles = [frames.get(name) for name in ("P50", "P95", "P99")]
    valid_samples = all(finite(p) and p >= 0 for p in percentiles)
    if not valid_samples or percentiles != sorted(percentiles):
        invalid.append("invalid_frame_percentiles")
    if not finite(frames.get("WindowCount")) or frames["WindowCount"] < 100:
        missing.append("frame_samples")
    target = context.get("TargetFPS", 30)
    if target not in (30, 60) or isinstance(target, bool):
        invalid.append("TargetFPS_must_be_30_or_60")
    elif valid_samples and capture.get("Context") == "StudioClient":
        if percentiles[1] > 1000 / target:
            budgets.append("frame_p95_exceeds_target")
    # Heartbeat interval is not hazard callback CPU time, network RTT or a client FPS claim.
    checkpoints = capture.get("Checkpoints")
    if not isinstance(checkpoints, list) or not checkpoints:
        missing.append("Checkpoints")
        checkpoints = []
    if any(not isinstance(p, dict) for p in checkpoints):
        invalid.append("invalid_checkpoint")
        checkpoints = [p for p in checkpoints if isinstance(p, dict)]
    scenario = context.get("Scenario")
    expected_rule = {"meteors": "MeteorRain", "reactor": "ReactorRush"}.get(scenario)
    if expected_rule and not any(p.get("RuleId") == expected_rule and p.get("Phase") == "Rule" for p in checkpoints):
        missing.append("requested_rule_not_observed")
    if scenario == "full_arena" and not any(p.get("Players") == 12 and p.get("ActivePlayers") == 12 and p.get("Phase") == "Rule" for p in checkpoints):
        missing.append("12_players_in_active_arena")
    if scenario == "full_arena" and clients != 12:
        missing.append("12_actual_clients")
    for metric in ("MemoryMb", "DataSendKbps", "DataReceiveKbps"):
        summary = capture.get(metric)
        if not isinstance(summary, dict) or not finite(summary.get("Count")) or summary["Count"] < 1:
            missing.append(metric)
            continue
        names = ("P50", "P95", "P99", "LifetimeMin", "LifetimeMean", "LifetimeMax")
        if any(name not in summary for name in names):
            missing.append(metric + "_summary")
            continue
        numbers = [summary[name] for name in names]
        if not all(finite(n) and n >= 0 for n in numbers):
            invalid.append(metric + "_nonfinite_summary")
        elif not (summary["LifetimeMin"] <= summary["LifetimeMean"] <= summary["LifetimeMax"]
                  and summary["LifetimeMin"] <= summary["P50"] <= summary["P95"] <= summary["P99"] <= summary["LifetimeMax"]):
            invalid.append(metric + "_summary_order")
    if capture.get("UnavailableMetrics"):
        result["unavailableMetrics"] = capture["UnavailableMetrics"]
    result["status"] = "Invalid" if invalid else "Incomplete" if missing else "NeedsInvestigation" if budgets else "ReadyForReview"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path("build/candidate-manifest.json"))
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--context", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    read = lambda path: json.loads(path.read_text(encoding="utf-8-sig")) if path else None
    report = assess(read(args.capture), read(args.context) or {}, read(args.manifest)["inputFingerprint"])
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    return 0 if report["status"] == "ReadyForReview" else 2


if __name__ == "__main__":
    raise SystemExit(main())
