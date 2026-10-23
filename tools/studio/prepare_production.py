"""Generate inspectable production-loop QA installers; no Studio control or publication.

Example: python tools/studio/prepare_production.py --output build/solo-production.luau
         --target-clients 1 --run-count 2 --second-case exact_four
The main output installs in Edit; .server/.client variants install in a running test.
Main must be disabled beforehand and enabled by the operator only after all native
clients/drivers are ready. No gameplay configuration or production Source is edited.
"""

import argparse
import hashlib
import json
from pathlib import Path

MARKER = "local QAOptions = {} -- QA_OPTIONS"
CASES = {"charged_die", "exact_four", "success"}


def normalize_options(target_clients, run_count, second_case):
    if type(target_clients) is not int or not 1 <= target_clients <= 12:
        raise ValueError("targetClients must be an integer in 1..12; native Studio capacity still applies")
    if type(run_count) is not int or run_count not in (1, 2):
        raise ValueError("runCount must be 1 or 2")
    if not isinstance(second_case, str) or second_case not in CASES:
        raise ValueError("secondCase must be charged_die, exact_four, or success")
    return {"targetClients": target_clients, "runCount": run_count, "secondCase": second_case}


def long_string(source):
    for size in range(1, 10):
        equals = "=" * size
        if f"]{equals}]" not in source:
            return f"[{equals}[{source}]{equals}]"
    raise ValueError("Cannot find a safe Luau long-string delimiter")


def install(name, class_name, parent, source):
    return (
        f"do local parent = {parent}\n"
        f"assert(not parent:FindFirstChild('{name}'), 'Existing QA fixture: {name}')\n"
        f"local item = Instance.new('{class_name}')\n"
        f"item.Name = '{name}'\nitem.Source = {long_string(source)}\nitem.Parent = parent\nend"
    )


def prepare(output, options, source_dir):
    monitor = (source_dir / "production_monitor.server.luau").read_text(encoding="utf-8-sig")
    driver = (source_dir / "rule_driver.client.luau").read_text(encoding="utf-8-sig")
    if monitor.count(MARKER) != 1:
        raise ValueError("QA_OPTIONS marker is missing or duplicated")
    literal = (
        "local QAOptions = { targetClients = " + str(options["targetClients"])
        + ", runCount = " + str(options["runCount"])
        + ", secondCase = " + json.dumps(options["secondCase"]) + " } -- QA_OPTIONS"
    )
    monitor = monitor.replace(MARKER, literal)
    preflight = [
        "assert(game:GetService('RunService'):IsStudio(), 'Studio only')",
        "assert(not game.ServerScriptService.RuleRoomServer.Main.Enabled, 'Disable Main BEFORE Play/install')",
        "assert(not game.ReplicatedStorage:FindFirstChild('QARuleCoverage'), 'Existing QA controller')",
    ]
    server_install = install("QAProductionMonitor", "Script", "game.ServerScriptService", monitor)
    starter_install = install("QARulesDriver", "LocalScript", "game.StarterPlayer.StarterPlayerScripts", driver)
    runtime_client_install = install("QARulesDriver", "LocalScript", "game.Players.LocalPlayer.PlayerScripts", driver)
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(preflight + [server_install, starter_install,
        "return { installed = 2, mainEnabled = false, requiresOperatorStart = true }"]) + "\n", encoding="utf-8")
    output.with_suffix(".server.luau").write_text("\n".join(preflight + [server_install,
        "return 'Production monitor installed; Main remains disabled'"]) + "\n", encoding="utf-8")
    output.with_suffix(".client.luau").write_text("\n".join([
        "assert(game:GetService('RunService'):IsStudio() and game:GetService('RunService'):IsClient(), 'Studio client only')",
        runtime_client_install,
        "return 'Driver installed on this native client; repeat for every target client'",
    ]) + "\n", encoding="utf-8")
    manifest = {
        "options": options,
        "cases": ["success"] + ([options["secondCase"]] if options["runCount"] == 2 else []),
        "monitorSha256": hashlib.sha256(monitor.encode("utf-8")).hexdigest(),
        "driverSha256": hashlib.sha256(driver.encode("utf-8")).hexdigest(),
        "results": "ReplicatedStorage.QARuleCoverage.EntryNNNN.Value; Complete indicates ended, Status/SummaryPassed indicate acceptance",
        "exactFourInjection": "Run 2 trials 1 and 2: current admitted Humanoid.Health=0 after >=1 second from observed Rule start. No counters or rewards changed.",
        "scope": "Production Main/Roster/ProfileService; Session only; no publication, DataStore, network settings, or gameplay configuration changes",
        "nativeClientLimit": "Operator must create targetClients real Studio clients; this tool creates none and does not bypass Studio capacity",
        "start": "Install monitor while Main disabled, install driver on every client, then operator enables Main",
    }
    output.with_suffix(".json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--target-clients", type=int, default=1)
    parser.add_argument("--run-count", type=int, choices=[1, 2], default=2)
    parser.add_argument("--second-case", choices=sorted(CASES), default="exact_four")
    args = parser.parse_args(argv)
    options = normalize_options(args.target_clients, args.run_count, args.second_case)
    manifest = prepare(args.output, options, Path(__file__).resolve().parent)
    print(f"Prepared {options['targetClients']} native clients / {manifest['cases']}; Main and Studio untouched")


if __name__ == "__main__":
    main()
