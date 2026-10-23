"""Static checks only. These do not substitute for a Studio playtest."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BIN = Path(os.environ.get('LOCALAPPDATA', str(ROOT / 'build'))) / 'RobloxDev' / 'bin'

def tool(name):
    candidate = BIN / (name + '.exe')
    if candidate.exists():
        return str(candidate)
    result = shutil.which(name)
    if not result:
        raise RuntimeError(f'Missing tool: {name}')
    return result

def run(args, quiet=False):
    result = subprocess.run(args, cwd=ROOT, text=True, encoding='utf-8',
                            stdout=subprocess.DEVNULL if quiet else None)
    if result.returncode:
        raise SystemExit(result.returncode)

run([tool('stylua'), '--check', 'src', 'tests'])
run([tool('selene'), 'src', 'tests'])
sources = sorted((ROOT / 'src').rglob('*.luau')) + sorted((ROOT / 'tests').rglob('*.luau'))
for source in sources:
    run([tool('luau-compile'), '--text', str(source)], quiet=True)
print(f'Static checks passed: {len(sources)} Luau files. Studio not implied.')
