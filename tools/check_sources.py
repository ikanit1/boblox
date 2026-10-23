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

source_dirs = ['src', 'tests']
studio_tools = ROOT / 'tools' / 'studio'
if studio_tools.is_dir():
    source_dirs.append('tools/studio')
run([tool('stylua'), '--check', *source_dirs])
run([tool('selene'), *source_dirs])
sources = sorted(source for folder in source_dirs for source in (ROOT / folder).rglob('*.luau'))
for source in sources:
    run([tool('luau-compile'), '--text', str(source)], quiet=True)
python_sources = sorted(studio_tools.rglob('*.py')) if studio_tools.is_dir() else []
if python_sources:
    # Compile syntax without importing or running installers/report scripts.
    run([sys.executable, '-m', 'py_compile', *(str(source) for source in python_sources)])
print(f'Static checks passed: {len(sources)} Luau files, {len(python_sources)} Python QA files. Studio not implied.')
