#!/usr/bin/env python3
"""Read-only Codex app-server discovery probe. Does not create threads or call MCP tools."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import queue
import shutil
import subprocess
import threading
import time

REPO = Path(__file__).resolve().parents[2]


def probe(executable: str, repository: Path, timeout: float) -> dict:
    process = subprocess.Popen([executable, "app-server", "--stdio"], cwd=repository,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, encoding="utf-8", bufsize=1)
    messages = queue.Queue()

    def read():
        for line in process.stdout:
            try:
                messages.put(json.loads(line))
            except json.JSONDecodeError:
                pass
        messages.put(None)

    threading.Thread(target=read, daemon=True).start()

    def request(identifier, method, params):
        process.stdin.write(json.dumps({"id": identifier, "method": method, "params": params}) + "\n")
        process.stdin.flush()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                message = messages.get(timeout=max(.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            if message is None:
                raise RuntimeError(f"App server closed before {method}")
            if message.get("id") == identifier:
                if "error" in message:
                    raise RuntimeError(f"{method}: {message['error']}")
                return message["result"]
        raise TimeoutError(f"Timed out during {method}")

    try:
        initialized = request(1, "initialize", {
            "clientInfo": {"name": "ruleroom-skill-discovery-audit", "version": "1.0"},
            "capabilities": {"experimentalApi": True, "explicitGatewayOauth": True}})
        process.stdin.write(json.dumps({"method": "initialized"}) + "\n")
        process.stdin.flush()
        result = request(2, "skills/list", {"cwds": [str(repository)], "forceReload": True})
        return {"initialize": initialized, "skillsList": result}
    finally:
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", default=shutil.which("codex"))
    parser.add_argument("--repo", type=Path, default=REPO)
    parser.add_argument("--timeout", type=float, default=60)
    args = parser.parse_args()
    if not args.codex:
        parser.error("Codex executable was not found")
    result = probe(args.codex, args.repo.resolve(), args.timeout)
    catalog_path = REPO / "docs/environment/skills-catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    expected = {row["name"] for row in catalog["skills"]}
    expected.update(("obsidian-gamedev-workflow", "roblox-development-orchestrator"))
    entries = result["skillsList"].get("data", [])
    skills = [skill for entry in entries for skill in entry.get("skills", [])]
    selected = [skill for skill in skills if skill.get("name") in expected]
    names = {skill["name"] for skill in selected}
    missing = sorted(expected - names)
    errors = [error for entry in entries for error in entry.get("errors", [])]
    relevant_errors = [e for e in errors if any(name in str(e) for name in expected)]
    disabled = [s["name"] for s in selected if s.get("enabled") is False]
    report = {"schemaVersion": 1, "observedAt": datetime.now(timezone.utc).isoformat(),
        "method": "Codex app-server initialize + skills/list(cwds=[repository], forceReload=true)",
        "codexVersion": subprocess.check_output([args.codex, "--version"], text=True).strip(),
        "repository": str(args.repo.resolve()), "expectedCount": len(expected),
        "discoveredExpectedCount": len(names), "selectedEntryCount": len(selected),
        "missing": missing, "disabled": disabled, "relevantErrors": relevant_errors,
        "unrelatedErrorCount": len(errors) - len(relevant_errors),
        "skills": selected, "passed": not missing and not disabled and not relevant_errors,
        "limits": "Metadata discovery only. No model invocation, natural-language routing, MCP calls, Blender/Studio workflow or bundled script execution."}
    path = REPO / "docs/environment/skills-discovery.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in catalog["skills"]:
        row["discovery"] = ("DISCOVERED_ENABLED" if row["name"] in names and row["name"] not in disabled
                            else "NOT_CONFIRMED")
    catalog["discoveryEvidence"] = "skills-discovery.json"
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("codexVersion", "expectedCount", "discoveredExpectedCount",
        "missing", "disabled", "relevantErrors", "unrelatedErrorCount", "passed")}, ensure_ascii=False))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

