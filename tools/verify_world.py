"""Geometry safety gates, independent of rendering and Roblox physics."""
from pathlib import Path
import math
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
root = ET.parse(ROOT / "assets/Arena.rbxmx").getroot()
world = root.find("Item")

def name(node):
    return node.findtext("Properties/string[@name='Name']")

def vector(node, kind, label):
    p = node.find(f"Properties/{kind}[@name='{label}']")
    return tuple(float(p.findtext(axis)) for axis in ("X", "Y", "Z"))

tiles = next(n for n in world.findall("Item") if name(n) == "Tiles")
assert len(tiles.findall("Item")) == 36
for tile in tiles.findall("Item"):
    assert vector(tile, "Vector3", "size") == (14, 2, 14)
    x, _, z = vector(tile, "CoordinateFrame", "CFrame")
    assert x in (-35, -21, -7, 7, 21, 35) and z in (-35, -21, -7, 7, 21, 35)
config = (ROOT / "src/shared/GameConfig.luau").read_text(encoding="utf-8")
assert re.search(r"ArenaHalfSize\s*=\s*42", config)
assert re.search(r"TileSize\s*=\s*14", config)
# No permanent collision inside the trial grid: holes must remain lethal and jumps unblocked.
for node in world.iter("Item"):
    if node in list(tiles) or name(node) in ("ArenaSpawn", "LobbySpawn", "Laser"):
        continue
    if node.findtext("Properties/bool[@name='CanCollide']") != "true":
        continue
    x, y, z = vector(node, "CoordinateFrame", "CFrame")
    sx, sy, sz = vector(node, "Vector3", "size")
    overlaps = abs(x) - sx / 2 < 42 - 0.001 and abs(z) - sz / 2 < 42 - 0.001
    assert not overlaps, f"Permanent geometry intrudes into hazards: {name(node)}"
course = {name(n): n for n in world.iter("Item") if re.fullmatch(r"Checkpoint[1-7]", name(n) or "")}
assert len(course) == 7
previous = (-64, 1.6, 150)
for index in range(1, 8):
    target = vector(course[f"Checkpoint{index}"], "CoordinateFrame", "CFrame")
    assert vector(course[f"Checkpoint{index}"], "Vector3", "size") == (12, 1, 12)
    dx, dy, dz = (target[i] - previous[i] for i in range(3))
    assert 0 < dy <= 2.1 and math.hypot(dx, dz) <= 15, f"Jump {index} out of budget"
    previous = target
assert len([n for n in world.iter("Item") if n.attrib["class"] == "ProximityPrompt"]) == 14
print("World safety passed: 84x84 grid, no permanent hazard refuge, 7 jump budgets, 14 stations.")
