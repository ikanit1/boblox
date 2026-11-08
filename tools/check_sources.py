"""Static checks only. These do not substitute for a Studio playtest."""
from pathlib import Path
import os
import re
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

# Instance properties shadow same-named children; dot indexing such a child returns the
# property instead (e.g. TextLabel.TextBounds is a Vector2, not the UITextSizeConstraint).
SHADOWED_CHILD = re.compile(r'\.TextBounds\.')
shadowed = []
for source in sorted((ROOT / 'src').rglob('*.luau')):
    for number, line in enumerate(source.read_text(encoding='utf-8').splitlines(), 1):
        if SHADOWED_CHILD.search(line):
            shadowed.append(f'{source.relative_to(ROOT)}:{number}: {line.strip()}')
if shadowed:
    print('Dot-indexed child shadowed by an Instance property; use WaitForChild/FindFirstChild:')
    print('\n'.join(shadowed))
    raise SystemExit(1)

folders = ['src', 'tests'] + (['prototypes'] if (ROOT / 'prototypes').is_dir() else [])
run([tool('stylua'), '--check', *folders])
run([tool('selene'), *folders])
sources = sorted(source for folder in folders for source in (ROOT / folder).rglob('*.luau'))
for source in sources:
    run([tool('luau-compile'), '--text', str(source)], quiet=True)
print(f'Static checks passed: {len(sources)} Luau files. Studio not implied.')
