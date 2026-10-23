"""Summarize isolated Studio evidence without promoting it to full Stage 1 acceptance.

Example (run from repository root):
  python tools/studio/summarize_acceptance.py --server evidence/server-export.json \
      --warnings evidence/warnings-summary.json --timers "evidence/timers-*.json" \
      --out evidence/acceptance-summary.json

Exit: 0 = all selected checks observed, 1 = failure, 2 = incomplete evidence.
Inputs are immutable. Output excludes verbose world snapshots and sample arrays.
The fixed budgets were declared before final analysis, not fitted to measurements.
"""

from __future__ import annotations

import argparse
from collections import Counter
import glob
import hashlib
import json
import math
from pathlib import Path
import re
import sys


SCHEDULES = {
    "SafeColor": [4.2, 1.8] * 3,
    "LaserSweep": [3, 15],
    "LowGravity": [3, 17],
    "RedLight": [2.4, 0.9, 2.7] * 3,
    "LavaRise": [4, 14],
    "MeteorRain": [3, 0.5] * 5,
    "DisappearingTiles": [3, 1.5] * 4,
    "SafeZone": [4.5, 1.5] * 3,
    "Spinner": [3, 15],
    "ReactorRush": [3, 19],
}
WARNING_INDEXES = {
    "SafeColor": [0, 2, 4], "LaserSweep": [0], "LowGravity": [0],
    "RedLight": [1, 4, 7], "LavaRise": [0], "MeteorRain": [0, 2, 4, 6, 8],
    "DisappearingTiles": [0, 2, 4, 6], "SafeZone": [0, 2, 4],
    "Spinner": [0], "ReactorRush": [0],
}
EPSILON = 0.001
MAX_SEGMENT_LATENESS = 0.25
MAX_WARNING_SHORTFALL = 0.25
STRICT_MIN_WARNING_LEAD = 0.2
TIMER_BUDGET = {"settleSeconds": 0.2, "sustainedMismatchSeconds": 0.25,
                "immediateDifferenceAbove": 1}


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def decode(value):
    if isinstance(value, str):
        try:
            return json.loads(value)
        except (ValueError, TypeError):
            pass
    return value


def payload(raw):
    """Accept plain exports and official MCP wrappers; a transport error never passes."""
    found, errors = [], []

    def walk(value, depth=0):
        if depth > 15:
            return
        value = decode(value)
        if isinstance(value, dict):
            if value.get("isError") is True:
                errors.append("MCP isError=true")
            if "jsonrpc" in value and value.get("error") is not None:
                errors.append("JSON-RPC error: " + str(value["error"])[:300])
            if ("attrs" in value and "entries" in value) or (
                "cases" in value and "caseCount" in value
            ):
                found.append(value)
                return
            if "qa" in value and isinstance(decode(value["qa"]), dict):
                walk(decode(value["qa"]), depth + 1)
            for key in ("result", "content", "text", "structuredContent"):
                if key in value:
                    walk(value[key], depth + 1)
        elif isinstance(value, list):
            for child in value:
                walk(child, depth + 1)

    walk(raw)
    if len(found) != 1:
        errors.append(f"Expected exactly one evidence payload, found {len(found)}")
    return (found[0] if found else {}), errors


def load(path):
    try:
        content = path.read_bytes()
        body, errors = payload(json.loads(content.decode("utf-8-sig")))
        return body, errors, {"path": str(path), "sha256": hashlib.sha256(content).hexdigest()}
    except (OSError, UnicodeError, ValueError) as exc:
        return {}, [f"{path}: {exc}"], {"path": str(path)}


def entries(body):
    result = []
    source = decode(body.get("entries", []))
    if isinstance(source, dict):
        source = [{"name": name, "value": value} for name, value in source.items()]
    if not isinstance(source, list):
        return result
    for ordinal, wrapper in enumerate(source, 1):
        item = decode(wrapper)
        name = ""
        if isinstance(item, dict) and "rule" not in item:
            name = str(item.get("name", item.get("Name", "")))
            for key in ("value", "Value", "json", "data", "text"):
                if key in item:
                    item = decode(item[key])
                    break
        if isinstance(item, dict):
            match = re.search(r"(\d+)$", name)
            result.append((int(match[1]) if match else ordinal, item))
    return result


def check(status, detail=None):
    result = {"status": status}
    if detail is not None:
        result["detail"] = detail
    return result


def truth(value, detail):
    return check("PASS" if value is True else "FAIL" if value is False else "UNVERIFIED", detail)


def combine(values):
    states = [v["status"] for v in values]
    return "FAIL" if "FAIL" in states else "UNVERIFIED" if not states or "UNVERIFIED" in states else "PASS"


def expected_scenarios(suite):
    cases = [(rule, "solve") for rule in SCHEDULES]
    if suite in ("core", "full"):
        cases += [(rule, "mistake") for rule in SCHEDULES]
    if suite == "full":
        cases += [("LaserSweep", "fatal_beam"), ("Spinner", "corner_idle")]
        cases += [(rule, "fault_reset") for rule in SCHEDULES]
    return cases


def server_checks(entry, clients):
    checks, metrics = {}, {}
    rule, behavior = entry.get("rule"), entry.get("behavior")
    schedule = SCHEDULES[rule]
    segments, players = entry.get("segments", []), entry.get("players", [])
    checks["fixture"] = truth(entry.get("ok"), entry.get("error"))
    names = [p.get("name") for p in players]
    checks["clientCount"] = truth(len(players) == clients and len(set(names)) == clients and all(names),
                                  {"actual": len(players), "expected": clients})
    cleanup = entry.get("cleanup", {})
    checks["productionCleanup"] = truth(
        cleanup.get("productionRestored") is True and cleanup.get("ok") is True
        and cleanup.get("recovery", {}).get("attempted") is False and not cleanup.get("errors"),
        "Production restoration is checked before fallback recovery.",
    )
    actual = [s.get("requestedSeconds") for s in segments]
    prefix_ok = bool(actual) and len(actual) <= len(schedule) and all(
        number(value) and abs(value - target) <= EPSILON for value, target in zip(actual, schedule)
    )
    full_needed = behavior == "solve" or entry.get("completed") is True
    # A rule may stop between subphases after the preceding segment reaches its deadline.
    early_dead = (entry.get("completed") is False and players and all(
        number(p.get("health")) and p["health"] <= 0 for p in players
    ))
    coverage_ok = prefix_ok and (len(actual) == len(schedule) or (not full_needed and early_dead))
    checks["segmentSchedule"] = truth(bool(coverage_ok), {"actual": actual, "expectedPositive": schedule})
    timer_errors, lateness = [], []
    for index, segment in enumerate(segments, 1):
        elapsed, requested, reason = segment.get("elapsed"), segment.get("requestedSeconds"), segment.get("reason")
        if not number(elapsed) or not number(requested):
            timer_errors.append(f"segment {index}: missing finite elapsed/requestedSeconds")
        elif reason == "deadline":
            late = elapsed - requested
            lateness.append(late)
            if late < -EPSILON or late > MAX_SEGMENT_LATENESS + EPSILON or segment.get("timerReached") is not True:
                timer_errors.append(f"segment {index}: deadline deviation {late:.6f}s or timerReached=false")
        elif reason != "no_alive_players" or not early_dead or index != len(segments):
            timer_errors.append(f"segment {index}: unsupported early-stop reason {reason!r}")
    checks["serverDeadline"] = check("FAIL" if timer_errors else "PASS" if segments else "UNVERIFIED", timer_errors)
    metrics["maxSegmentLatenessSeconds"] = max(lateness) if lateness else None
    metrics["durationSeconds"] = entry.get("duration")
    checks["movement"] = truth(all(p.get("movement") == "" for p in players) if players else None,
                               [p.get("movement") for p in players])
    reward_ok = bool(players)
    for player in players:
        awards = player.get("awardCalls", {})
        reward_ok = reward_ok and player.get("survivalAwardOnce") is True and player.get("completionAwardOnce") is True
        reward_ok = reward_ok and awards.get("survival") in (0, 1) and awards.get("completion") in (0, 1)
        if number(player.get("health")) and player["health"] <= 0:
            reward_ok = reward_ok and awards.get("survival") == 0 and awards.get("wins") == 0
    checks["mockAwardsOnce"] = truth(bool(reward_ok), "Duplicate roster calls; not unique-pickup or real ProfileService verification.")
    outcome = None
    if behavior == "solve":
        # Health can regenerate after elimination. Positive HP alone is not a successful solve.
        outcome = bool(players) and entry.get("completed") is True and all(
            number(p.get("health")) and p["health"] > 0
            and p.get("inRound") is True
            and p.get("awardCalls", {}).get("survival") == 1
            and p.get("awardCalls", {}).get("completion") == 1 for p in players
        )
        if rule == "LowGravity":
            # Pickups are finite and shared. The rule does not guarantee one per player.
            outcome = outcome and sum(p.get("awardCalls", {}).get("stars", 0) for p in players) > 0
        if rule == "ReactorRush":
            outcome = outcome and entry.get("finale") is True and number(entry.get("goal")) and entry["goal"] > 0 and entry.get("charge", 0) >= entry["goal"]
    elif behavior in ("mistake", "corner_idle", "no_collect"):
        outcome = entry.get("failureOutcome") == "achieved"
    elif behavior == "fatal_beam":
        outcome = bool(early_dead) and entry.get("injection", {}).get("applied") is False
    elif behavior == "fault_reset":
        outcome = bool(early_dead) and entry.get("injection", {}).get("applied") is True
    checks["outcome"] = truth(outcome, entry.get("failureOutcome", "explicit behavior check"))
    metrics["players"] = [{k: p.get(k) for k in ("name", "health", "minHealth", "maxY", "awardCalls")} for p in players]
    metrics["charge"] = entry.get("charge")
    metrics["goal"] = entry.get("goal")
    metrics["finale"] = entry.get("finale")
    metrics["injectionApplied"] = entry.get("injection", {}).get("applied")
    return checks, metrics


def warning_checks(case, entry, profile):
    if case is None:
        return {"observer": check("UNVERIFIED", "Missing matching client warning case")}, {}
    checks = {"observer": truth(case.get("observationComplete"), "Complete, non-truncated observation from the case boundary.")}
    segments = entry.get("segments", [])
    rule = entry["rule"]
    warning_indexes = [i for i in WARNING_INDEXES[rule] if i < len(segments)]
    active_indexes = [i for i in WARNING_INDEXES[rule] if i + 1 < len(segments)]
    warnings, activations = case.get("warnings", []), case.get("activations", [])
    counts = {"warnings": len(warnings), "expectedWarnings": len(warning_indexes),
              "activations": len(activations), "expectedActivations": len(active_indexes)}
    complete = case.get("observationComplete") is True
    checks["subphaseCoverage"] = check(
        "PASS" if complete and len(warnings) == len(warning_indexes) and len(activations) == len(active_indexes)
        else "UNVERIFIED", counts,
    )
    leads, lead_errors, unknown = [], [], False
    for ordinal, activation in enumerate(activations):
        at, warning_at = activation.get("at"), activation.get("warningHudFullyReadableAt")
        if not number(at) or not number(warning_at) or ordinal >= len(active_indexes):
            unknown = True
            continue
        lead = at - warning_at
        leads.append(lead)
        configured = SCHEDULES[rule][active_indexes[ordinal]]
        if lead <= STRICT_MIN_WARNING_LEAD:
            lead_errors.append(f"activation {ordinal + 1}: lead {lead:.6f}s is not strictly >0.2s")
        if profile == "local-zero" and lead + EPSILON < configured - MAX_WARNING_SHORTFALL:
            lead_errors.append(f"activation {ordinal + 1}: lead {lead:.6f}s < {configured - MAX_WARNING_SHORTFALL:.3f}s")
    if not active_indexes and not activations:
        checks["warningLead"] = check("PASS", "No active hazard reached; injected early reset does not establish gameplay warning timing.")
    else:
        checks["warningLead"] = check("FAIL" if lead_errors else "UNVERIFIED" if unknown or not complete or len(leads) != len(active_indexes) else "PASS", lead_errors)
    if profile == "delayed" and active_indexes:
        checks["configuredWarningBudget"] = check("NOT_APPLICABLE", "Zero-delay shortfall budget does not transfer to delayed replication; the >0.2s lead check still applies and actual leads are reported.")
    damage = case.get("firstDamage")
    if entry.get("injection", {}).get("applied") is True:
        checks["warningBeforeDamage"] = check("PASS", "Injected damage excluded from natural hazard warning evaluation.")
    elif damage is None:
        checks["warningBeforeDamage"] = check("PASS", "No damage observed; this alone does not prove warning timing.")
    else:
        damage_at = damage.get("at")
        prior = [w.get("hudFullyReadableAt") for w in warnings if number(w.get("hudFullyReadableAt"))
                 and number(damage_at) and w["hudFullyReadableAt"] <= damage_at]
        checks["warningBeforeDamage"] = check(
            "UNVERIFIED" if not prior or not complete else
            "PASS" if damage_at - max(prior) > STRICT_MIN_WARNING_LEAD else "FAIL",
            {"fullyReadableWarningLeadToFirstDamageSeconds": damage_at - max(prior) if prior else None},
        )
    hud_samples = case.get("visibleMatchingHudSamples", 0)
    checks["hudGeometry"] = check("FAIL" if case.get("clippingExamples") or case.get("textOverflowExamples")
                                  else "PASS" if hud_samples > 0 and complete else "UNVERIFIED",
                                  {"clipping": len(case.get("clippingExamples", [])), "overflow": len(case.get("textOverflowExamples", []))})
    checks["clientCleanup"] = truth(case.get("cleanupExactBaselineMatch") if case.get("cleanupBaselineAvailable") is True else None,
                                   "Exact replicated baseline, not only a heuristic clear-world check.")
    return checks, {**counts, "minFullyReadableWarningLeadSeconds": min(leads) if leads else None,
                    "maxFullyReadableWarningLeadSeconds": max(leads) if leads else None,
                    "damageOrder": case.get("damageOrder"), "userId": case.get("userId")}


def timer_check(case):
    if case is None:
        return check("UNVERIFIED", "No matching client timer observation")
    counters = ("issueCount", "negativeSamples", "nonNumericSamples", "missingDeadlineSamples")
    detail = {k: case.get(k) for k in counters + ("evaluatedSamples", "maxDifference", "maxMismatchDuration", "startedMidRule")}
    if any(number(case.get(k)) and case[k] > 0 for k in counters):
        return check("FAIL", detail)
    if any(case.get(k) != 0 for k in counters):
        return check("UNVERIFIED", detail)
    if (case.get("startedMidRule") is not False or case.get("truncated") is not False
            or case.get("status") != "observed_within_tolerance" or case.get("evaluatedSamples", 0) <= 0):
        return check("UNVERIFIED", detail)
    if any(case.get("tolerance", {}).get(k) != value for k, value in TIMER_BUDGET.items()):
        return check("UNVERIFIED", "Observer thresholds differ from the declared timer budget")
    return check("PASS", detail)


def summarize(server, warning_body, timers, *, clients=2, suite="full", profile="local-zero", input_errors=None):
    input_errors = input_errors or []
    server_entries = entries(server)
    warning_cases = warning_body.get("cases", [])
    timer_cases = [entry for body in timers for _, entry in entries(body)]
    observed = [(e.get("rule"), e.get("behavior")) for _, e in server_entries]
    expected = expected_scenarios(suite)
    checks = {"inputIntegrity": check("FAIL" if input_errors else "PASS", input_errors),
              "fixtureComplete": truth(server.get("attrs", {}).get("Complete"), "Complete is fixture termination, not gameplay success."),
              "scenarioCoverage": check("PASS" if all(observed.count(pair) == 1 for pair in expected) else "UNVERIFIED",
                                        {"expected": len(expected), "observed": len(server_entries),
                                         "missingOrDuplicate": [list(pair) for pair in expected if observed.count(pair) != 1]})}
    rows, used_warning, used_timer = [], set(), set()
    for index, entry in server_entries:
        rule, behavior = entry.get("rule"), entry.get("behavior")
        if rule not in SCHEDULES:
            checks[f"unknownEntry{index}"] = check("FAIL", f"Unknown rule {rule!r}")
            continue
        row_checks, metrics = server_checks(entry, clients)
        row = {"entryIndex": index, "rule": rule, "behavior": behavior, "server": row_checks,
               "metrics": metrics, "clients": []}
        for player in entry.get("players", []):
            matches = [(n, c) for n, c in enumerate(warning_cases)
                       if (c.get("entryIndex"), c.get("rule"), c.get("behavior"), c.get("playerName"))
                       == (index, rule, behavior, player.get("name"))]
            warning = matches[0][1] if len(matches) == 1 else None
            used_warning.update(n for n, _ in matches)
            client_checks, client_metrics = warning_checks(warning, entry, profile)
            if len(matches) > 1:
                client_checks["observer"] = check("UNVERIFIED", "Multiple matching warning cases; no silent deduplication")
            timer_matches = [(n, c) for n, c in enumerate(timer_cases) if warning and
                             (c.get("entryIndex"), c.get("rule"), c.get("behavior"), c.get("userId"))
                             == (index, rule, behavior, warning.get("userId"))]
            used_timer.update(n for n, _ in timer_matches)
            client_checks["timer"] = timer_check(timer_matches[0][1] if len(timer_matches) == 1 else None)
            row["clients"].append({"name": player.get("name"), "checks": client_checks, "metrics": client_metrics})
        all_checks = list(row_checks.values()) + [v for c in row["clients"] for v in c["checks"].values()]
        row["status"] = combine(all_checks)
        rows.append(row)
    flat = list(checks.values()) + [v for r in rows for v in r["server"].values()] + [v for r in rows for c in r["clients"] for v in c["checks"].values()]
    orphan_warning = [{k: c.get(k) for k in ("playerName", "entryIndex", "rule", "behavior", "key")} for n, c in enumerate(warning_cases) if n not in used_warning]
    orphan_timer = [{k: c.get(k) for k in ("userId", "entryIndex", "rule", "behavior", "key")} for n, c in enumerate(timer_cases) if n not in used_timer]
    return {"schemaVersion": 1, "status": combine(flat), "scope": "Selected isolated fixture checks; not full Stage 1 or multiplayer acceptance.",
            "suite": suite, "profile": profile, "expectedClients": clients,
            "budgets": {"epsilonSeconds": EPSILON, "maxSegmentLatenessSeconds": MAX_SEGMENT_LATENESS,
                        "zeroDelayWarningShortfallSeconds": MAX_WARNING_SHORTFALL,
                        "strictMinimumWarningLeadSeconds": STRICT_MIN_WARNING_LEAD, "timer": TIMER_BUDGET},
            "checks": checks, "checkCounts": dict(Counter(c["status"] for c in flat)),
            "rowCounts": dict(Counter(r["status"] for r in rows)), "rows": rows,
            "orphanWarnings": orphan_warning, "orphanTimers": orphan_timer,
            "limits": ["Render eligibility and geometry are not pixel visibility or human readability.",
                       "Mock awards do not prove cloud saves, production economy, or unique pickup idempotency.",
                       "Injected resets are distinct from natural death and manual Roblox Reset Character.",
                       "This file does not certify solo/full Main, exact-four qualification, or 12 clients."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, default=Path("evidence/server-export.json"))
    parser.add_argument("--warnings", type=Path, default=Path("evidence/warnings-summary.json"))
    parser.add_argument("--timers", nargs="*", default=[])
    parser.add_argument("--clients", type=int, default=2)
    parser.add_argument("--suite", choices=("solve", "core", "full"), default="full")
    parser.add_argument("--profile", choices=("local-zero", "delayed"), default="local-zero")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.clients < 1:
        parser.error("--clients must be positive")
    paths, errors, provenance = [args.server, args.warnings], [], []
    for pattern in args.timers:
        matches = sorted(glob.glob(pattern))
        if not matches:
            errors.append("Timer pattern matched no files: " + pattern)
        paths.extend(Path(path) for path in matches)
    # Repeated paths must not create false duplicate observations.
    paths = list(dict.fromkeys(path.resolve() for path in paths))
    if args.out and args.out.resolve() in paths:
        parser.error("--out cannot overwrite an input")
    bodies = []
    for path in paths:
        body, messages, source = load(path)
        bodies.append(body)
        errors.extend(messages)
        provenance.append(source)
    result = summarize(bodies[0], bodies[1] if len(bodies) > 1 else {}, bodies[2:], clients=args.clients,
                       suite=args.suite, profile=args.profile, input_errors=errors)
    result["sources"] = provenance
    encoded = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(encoded, encoding="utf-8")
    for row in result["rows"]:
        bad = [name for name, value in row["server"].items() if value["status"] != "PASS"]
        bad += [f"{c['name']}:{name}={value['status']}" for c in row["clients"] for name, value in c["checks"].items() if value["status"] not in ("PASS", "NOT_APPLICABLE")]
        print(f"{row['entryIndex']:02d} {row['rule']:<19} {row['behavior']:<12} {row['status']:<10} " + ", ".join(bad))
    print(json.dumps({k: result[k] for k in ("status", "checkCounts", "rowCounts", "orphanWarnings", "orphanTimers")}, ensure_ascii=True))
    if errors:
        print("Input errors: " + "; ".join(errors), file=sys.stderr)
    if args.out:
        print("Wrote " + str(args.out))
    return {"PASS": 0, "FAIL": 1, "UNVERIFIED": 2}[result["status"]]


if __name__ == "__main__":
    sys.exit(main())
