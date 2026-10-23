"""Prepare inspectable Studio-only QA scripts; never starts Studio or publishes a place."""
import argparse
import json
from pathlib import Path

RULES = ['SafeColor', 'LaserSweep', 'LowGravity', 'RedLight', 'LavaRise',
         'MeteorRain', 'DisappearingTiles', 'SafeZone', 'Spinner', 'ReactorRush']

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--suite', choices=['complete', 'solve', 'negative', 'reset'], default='complete')
args = parser.parse_args()
source_dir = Path(__file__).resolve().parent
scenarios = []
if args.suite in ('complete', 'solve'):
    scenarios += [{'rule': rule, 'behavior': 'solve'} for rule in RULES]
if args.suite in ('complete', 'negative'):
    scenarios += [{'rule': rule, 'behavior': 'mistake'} for rule in RULES]
    scenarios += [{'rule': 'LaserSweep', 'behavior': 'fatal_beam'},
                  {'rule': 'Spinner', 'behavior': 'corner_idle'}]
if args.suite in ('complete', 'reset'):
    scenarios += [{'rule': rule, 'behavior': 'fault_reset'} for rule in RULES]
server = (source_dir / 'rule_coverage.server.luau').read_text(encoding='utf-8-sig')
marker = 'local requestedScenarios = nil -- QA_SCENARIOS'
assert server.count(marker) == 1
server = server.replace(marker, 'local requestedScenarios = Http:JSONDecode([=[' + json.dumps(scenarios) + ']=]) -- QA_SCENARIOS')
sources = [
    ('QARules', 'Script', 'game.ServerScriptService', server),
    ('QARulesDriver', 'LocalScript', 'game.StarterPlayer.StarterPlayerScripts', (source_dir / 'rule_driver.client.luau').read_text(encoding='utf-8-sig')),
    ('QAWarningObserver', 'LocalScript', 'game.StarterPlayer.StarterPlayerScripts', (source_dir / 'warning_observer.client.luau').read_text(encoding='utf-8-sig')),
    ('QATimerObserver', 'LocalScript', 'game.StarterPlayer.StarterPlayerScripts', (source_dir / 'timer_observer.client.luau').read_text(encoding='utf-8-sig')),
]
code = ["assert(game:GetService('RunService'):IsStudio())", "assert(not game.ServerScriptService.RuleRoomServer.Main.Enabled)"]
runtime_server = code.copy()
runtime_client = ["assert(game:GetService('RunService'):IsStudio())"]
for name, kind, parent, source in sources:
    assert ']==]' not in source
    code += [f"do local parent={parent}; assert(not parent:FindFirstChild('{name}'), 'Existing QA fixture');",
             f"local s=Instance.new('{kind}');s.Name='{name}';s.Source=[==[{source}]==];s.Parent=parent;end"]
    runtime = runtime_server if kind == 'Script' else runtime_client
    runtime_parent = parent if kind == 'Script' else 'game.Players.LocalPlayer.PlayerScripts'
    runtime += [f"do local parent={runtime_parent}; assert(not parent:FindFirstChild('{name}'), 'Existing QA fixture');",
                f"local s=Instance.new('{kind}');s.Name='{name}';s.Source=[==[{source}]==];s.Parent=parent;end"]
code.append(f"return {{installed=4,scenarios={len(scenarios)},startRequiresOperator=true}}")
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text('\n'.join(code), encoding='utf-8')
args.output.with_suffix('.server.luau').write_text('\n'.join(runtime_server + ["return 'Server QA installed; Start=false'"]), encoding='utf-8')
args.output.with_suffix('.client.luau').write_text('\n'.join(runtime_client + ["return 'Client observer and driver installed'"]), encoding='utf-8')
args.output.with_suffix('.json').write_text(json.dumps({'suite': args.suite, 'scenarios': scenarios}, indent=2) + '\n', encoding='utf-8')
print(f'Prepared {len(scenarios)} cases; no Studio state changed')
