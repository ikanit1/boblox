"""Install this repository's two coordinator skills; refuse foreign or user-edited targets."""
import hashlib
import json
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex'))) / 'skills'
STATE = Path(os.environ['LOCALAPPDATA']) / 'RobloxDev/project-skills.lock.json'
OWNER = 'https://github.com/ikanit1/boblox'

def hashes(folder):
    return {str(p.relative_to(folder)).replace('\\', '/'): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(folder.rglob('*')) if p.is_file()}

def main():
    state = json.loads(STATE.read_text()) if STATE.exists() else {'owner': OWNER, 'skills': {}}
    assert state['owner'] == OWNER, 'Installation ownership differs'
    DEST.mkdir(parents=True, exist_ok=True)
    for name in ['roblox-development-orchestrator', 'obsidian-gamedev-workflow']:
        source, target = ROOT / '.agents/skills' / name, DEST / name
        wanted = hashes(source)
        assert wanted and 'SKILL.md' in wanted
        if target.exists():
            old = state['skills'].get(name)
            actual = hashes(target)
            assert actual == wanted or (old and actual == old['hashes']), 'Preserve foreign or edited skill: ' + name
            assert set(actual) <= set(wanted), 'Preserve existing extra files: ' + name
            shutil.copytree(source, target, dirs_exist_ok=True)
        else:
            shutil.copytree(source, target)
        assert hashes(target) == wanted
        state['skills'][name] = {'path': str(target), 'hashes': wanted}
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2) + '\n')
    print(json.dumps({'installed': state['skills'], 'discovery': 'Run Codex skills/list; new skill metadata is loaded on a following turn.'}))

if __name__ == '__main__':
    main()
