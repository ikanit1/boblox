"""Parse read-only QAWarningEvidence exports. No Studio access or production writes.

Usage:
  python work/setup/parse_warning_observer.py export.json [more.json ...] --out summary.json
Accepts raw case objects/lists, {name,value} exports, and MCP result/content/text wrappers.
No observed damage is reported as no_damage, never as a warning timing pass.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

RULES = (
    "SafeColor", "LaserSweep", "LowGravity", "RedLight", "LavaRise",
    "MeteorRain", "DisappearingTiles", "SafeZone", "Spinner", "ReactorRush",
)


def cases_from(value: Any):
    if isinstance(value, str):
        stripped = value.strip()
        if stripped.startswith(("{", "[")):
            try:
                yield from cases_from(json.loads(stripped))
            except json.JSONDecodeError:
                return
    elif isinstance(value, list):
        for item in value:
            yield from cases_from(item)
    elif isinstance(value, dict):
        if value.get("schemaVersion") == 1 and isinstance(value.get("events"), list) and value.get("rule"):
            yield value
        else:
            for item in value.values():
                yield from cases_from(item)


def visible_matching(event: dict) -> bool:
    hud = event.get("hud", {})
    return bool(hud.get("exists") and hud.get("renderEligible")
                and hud.get("matchesInstruction") and hud.get("text"))


def seconds(start: Any, end: Any):
    if isinstance(start, (int, float)) and isinstance(end, (int, float)):
        return round(end - start, 4)
    return None


def analyze_case(case: dict) -> dict:
    events = case.get("events", [])
    warnings: list[dict] = []
    activations: list[dict] = []
    current_warning = None
    previous_stage = None
    hud_mismatches, clipped, overflow = [], [], []
    eligible_count = 0
    for event in events:
        if event.get("phase") != "Rule" or event.get("rule") != case.get("rule"):
            continue
        hud = event.get("hud", {})
        at = event.get("at")
        if visible_matching(event):
            eligible_count += 1
        elif len(hud_mismatches) < 12:
            hud_mismatches.append({
                "at": at, "instruction": event.get("instruction"),
                "text": hud.get("text"), "renderEligible": hud.get("renderEligible"),
                "matchesInstruction": hud.get("matchesInstruction"),
            })
        if hud.get("renderEligible") and hud.get("fullyOnScreen") is False and len(clipped) < 8:
            clipped.append({"at": at, "rect": hud.get("rect"), "text": hud.get("text")})
        if hud.get("renderEligible") and hud.get("textFits") is False and len(overflow) < 8:
            overflow.append({"at": at, "rect": hud.get("rect"), "text": hud.get("text")})
        stage = event.get("stage")
        if stage == "warning":
            if previous_stage != "warning" or current_warning is None:
                current_warning = {
                    "at": at, "instruction": event.get("instruction"),
                    "evidence": event.get("stageEvidence"),
                    "hudVisibleAt": None, "hudFullyReadableAt": None,
                    "world": event.get("world"),
                }
                warnings.append(current_warning)
            if visible_matching(event):
                if current_warning["hudVisibleAt"] is None:
                    current_warning["hudVisibleAt"] = at
                if hud.get("fullyOnScreen") and hud.get("textFits") is True:
                    if current_warning["hudFullyReadableAt"] is None:
                        current_warning["hudFullyReadableAt"] = at
        elif stage == "active" and previous_stage != "active":
            lead = seconds(current_warning.get("hudVisibleAt"), at) if current_warning else None
            activations.append({
                "at": at, "evidence": event.get("stageEvidence"),
                "instruction": event.get("instruction"), "world": event.get("world"),
                "warningAt": current_warning.get("at") if current_warning else None,
                "warningHudVisibleAt": current_warning.get("hudVisibleAt") if current_warning else None,
                "warningHudFullyReadableAt": current_warning.get("hudFullyReadableAt") if current_warning else None,
                "visibleWarningLeadSeconds": lead,
                "warningOrder": "observed_before_or_same_sample" if lead is not None and lead >= 0
                    else "not_observed",
                "samplingCaveat": "Same-sample or ~50ms ordering cannot establish actual server onset.",
            })
            current_warning = None
        elif stage in ("green", "none", "outside"):
            current_warning = None
        previous_stage = stage

    first_damage = case.get("firstDamage")
    prior_visible_warnings = [
        item for item in warnings if item.get("hudVisibleAt") is not None
        and first_damage and item["hudVisibleAt"] <= first_damage.get("at", float("-inf"))
    ]
    nearest_warning = prior_visible_warnings[-1] if prior_visible_warnings else None
    damage_order = "no_damage"
    lead_to_damage = None
    if first_damage:
        damage_order = "visible_warning_preceded_damage" if nearest_warning else "no_prior_visible_warning_observed"
        if nearest_warning:
            lead_to_damage = seconds(nearest_warning["hudVisibleAt"], first_damage.get("at"))
    cleanup = case.get("cleanup") or {}
    partial = bool(case.get("startedMidRule"))
    truncated = bool(case.get("truncated") or case.get("damageTruncated"))
    complete_reason = case.get("closedReason") in ("next_case_boundary", "main_trial_boundary", "coverage_complete")
    return {
        "userId": case.get("userId"), "playerName": case.get("playerName"),
        "key": case.get("key"), "rule": case.get("rule"), "behavior": case.get("behavior"),
        "entryIndex": case.get("entryIndex"), "startedMidRule": partial,
        "closedReason": case.get("closedReason"), "truncated": truncated,
        "eventCount": len(events), "visibleMatchingHudSamples": eligible_count,
        "warnings": warnings, "activations": activations,
        "missingWarningForActivationCount": sum(a["warningOrder"] == "not_observed" for a in activations),
        "firstDamage": first_damage, "damageEventCount": len(case.get("damage", [])),
        "damageOrder": damage_order, "visibleWarningLeadToFirstDamageSeconds": lead_to_damage,
        "hudMismatchExamples": hud_mismatches, "clippingExamples": clipped, "textOverflowExamples": overflow,
        "cleanupExactBaselineMatch": cleanup.get("exactBaselineMatch"),
        "cleanupBaselineAvailable": cleanup.get("baselineAvailable", False),
        "cleanupHeuristicClear": cleanup.get("heuristicClear"),
        "cleanupObservedAt": (cleanup.get("sample") or {}).get("at"),
        "observationComplete": complete_reason and not partial and not truncated,
        "acceptance": "review_observations_not_automatic_pass",
        "limits": case.get("limits"),
    }


def analyze(cases: list[dict]) -> dict:
    unique = {(case.get("userId"), case.get("key"), case.get("openedAt")): case for case in cases}
    results = [analyze_case(case) for case in unique.values()]
    results.sort(key=lambda item: (str(item.get("userId")), item.get("entryIndex") or 0, str(item.get("key"))))
    seen = {item["rule"] for item in results}
    return {
        "schemaVersion": 1,
        "evidence": "Client render-eligible HUD and replicated world transitions; no pixel/occlusion or human-readability guarantee.",
        "caseCount": len(results), "clientIds": sorted({str(item.get("userId")) for item in results}),
        "rulesObserved": [rule for rule in RULES if rule in seen],
        "rulesMissing": [rule for rule in RULES if rule not in seen],
        "partialCases": sum(item["startedMidRule"] for item in results),
        "truncatedCases": sum(item["truncated"] for item in results),
        "unobservedWarningActivations": sum(item["missingWarningForActivationCount"] for item in results),
        "cases": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    cases = []
    for path in args.inputs:
        with path.open(encoding="utf-8-sig") as stream:
            cases.extend(cases_from(json.load(stream)))
    summary = analyze(cases)
    encoded = json.dumps(summary, ensure_ascii=False, indent=2)
    if args.out:
        args.out.write_text(encoded + "\n", encoding="utf-8")
        print(json.dumps({key: summary[key] for key in (
            "caseCount", "clientIds", "rulesObserved", "rulesMissing",
            "partialCases", "truncatedCases", "unobservedWarningActivations",
        )}, ensure_ascii=False, indent=2))
    else:
        print(encoded)
    if not cases:
        print("No schemaVersion=1 warning cases found; this is not a successful observation.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
