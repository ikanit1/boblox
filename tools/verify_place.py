"""Check the built Rojo place's execution locations and authored content."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PLACE = ROOT / 'build' / 'RuleRoom.rbxlx'
tree = ET.parse(PLACE).getroot()

def name(node):
    return node.findtext("Properties/string[@name='Name']", default='')

def child(node, label, cls=None):
    matches = [item for item in node.findall('Item') if name(item) == label]
    assert len(matches) == 1, f'Expected one {label}, got {len(matches)}'
    result = matches[0]
    assert cls is None or result.attrib['class'] == cls, f'{label} wrong class'
    return result

workspace = child(tree, 'Workspace', 'Workspace')
arena = child(workspace, 'Arena', 'Model')
tiles = child(arena, 'Tiles', 'Folder').findall('Item')
assert len(tiles) == 36
assert all(t.attrib['class'] == 'Part' for t in tiles)
for tile in tiles:
    assert tile.findtext("Properties/bool[@name='Anchored']") == 'true'
    assert tile.findtext("Properties/bool[@name='CanCollide']") == 'true'
    child(child(tile, 'TileLabel', 'SurfaceGui'), 'ColorText', 'TextLabel')
child(arena, 'ArenaSpawn', 'Part')
child(arena, 'LobbySpawn', 'SpawnLocation')
laser = child(arena, 'Laser', 'Part')
assert laser.findtext("Properties/float[@name='Transparency']") == '1'
assert laser.findtext("Properties/bool[@name='CanCollide']") == 'false'
shared = child(child(tree, 'ReplicatedStorage'), 'RuleRoomShared')
child(shared, 'GameConfig', 'ModuleScript')
server = child(child(tree, 'ServerScriptService'), 'RuleRoomServer')
assert any(item.attrib['class'] == 'Script' for item in server.iter('Item'))
client = child(child(child(tree, 'StarterPlayer'), 'StarterPlayerScripts'), 'RuleRoomClient')
assert any(item.attrib['class'] == 'LocalScript' for item in client.iter('Item'))
gui = child(child(tree, 'StarterGui'), 'RuleRoomHUD', 'ScreenGui')
assert gui.findtext("Properties/bool[@name='ResetOnSpawn']") == 'false'
root = child(gui, 'Root', 'Frame')
child(child(root, 'RulePanel'), 'Timer')
remotes = child(child(tree, 'ReplicatedStorage'), 'RuleRoomRemotes', 'Folder')
child(remotes, 'Vote', 'RemoteEvent')
child(remotes, 'ProfileAction', 'RemoteEvent')
assert len([item for item in tree.iter('Item') if item.attrib['class'] == 'RemoteEvent']) == 2
assert not any(item.attrib['class'] == 'RemoteFunction' for item in tree.iter('Item'))
report = {
    'verification_level': 'static_place_structure',
    'studio_playtest': False,
    'tiles': len(tiles),
    'instances': len(list(tree.iter('Item'))),
    'scripts': [name(item) for item in tree.iter('Item') if item.attrib['class'] in ('Script', 'LocalScript', 'ModuleScript')],
}
(ROOT / 'build' / 'structure-check.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(f"Built place structure passed: {report['instances']} instances, 36 labeled tiles, server/client mapping.")
