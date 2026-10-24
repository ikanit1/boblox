"""Build editable Roblox model XML from deterministic, dependency-free sources.

The models contain no scripts, Toolbox assets, remote images, or paid content.
Run from anywhere with Python 3: python tools/build_assets.py.
"""

from __future__ import annotations

import base64
import itertools
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
import build_station

ROOT = Path(__file__).resolve().parents[1]
NAVY = (18, 30, 50)
PANEL = (24, 36, 57)
WHITE = (246, 248, 255)
MUTED = (179, 197, 219)
COLORS = [
    ("Blue", "СИНИЙ", "●", (70, 168, 244)),
    ("Pink", "РОЗОВЫЙ", "◆", (255, 115, 173)),
    ("Yellow", "ЖЁЛТЫЙ", "▲", (255, 213, 79)),
    ("Green", "ЗЕЛЁНЫЙ", "■", (66, 220, 169)),
]
_ids = itertools.count(1)


def item(parent, cls: str, name: str):
    node = ET.SubElement(parent, "Item", {"class": cls, "referent": f"RBX{next(_ids):06d}"})
    ET.SubElement(node, "Properties")
    prop(node, "string", "Name", name)
    return node


def prop(node, kind: str, name: str, value):
    props = node.find("Properties")
    assert props is not None
    element = ET.SubElement(props, kind, {"name": name})
    if kind == "bool":
        element.text = "true" if value else "false"
    elif kind in ("Vector2", "Vector3"):
        for key, val in zip(("X", "Y", "Z"), value):
            ET.SubElement(element, key).text = str(val)
    elif kind == "Color3":
        for key, val in zip(("R", "G", "B"), value):
            ET.SubElement(element, key).text = f"{val / 255:.8f}"
    elif kind == "UDim2":
        for key, val in zip(("XS", "XO", "YS", "YO"), value):
            ET.SubElement(element, key).text = str(val)
    elif kind == "UDim":
        for key, val in zip(("S", "O"), value):
            ET.SubElement(element, key).text = str(val)
    elif kind == "CoordinateFrame":
        for key, val in zip(("X", "Y", "Z"), value[:3]):
            ET.SubElement(element, key).text = str(val)
        rotation = value[3:] or (1, 0, 0, 0, 1, 0, 0, 0, 1)
        for key, val in zip(("R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"), rotation):
            ET.SubElement(element, key).text = str(val)
    elif kind == "Font":
        family = ET.SubElement(element, "Family")
        ET.SubElement(family, "url").text = "rbxasset://fonts/families/BuilderSans.json"
        ET.SubElement(element, "Weight").text = str(value)
        ET.SubElement(element, "Style").text = "Normal"
    else:
        element.text = str(value)
    return element


def attrs(node, values: dict[str, str]):
    # Roblox AttributesSerialize: LE count, LE length-prefixed UTF-8 name,
    # string type 0x02, LE length-prefixed UTF-8 value. See rbx-dom attributes/writer.rs.
    data = bytearray(struct.pack("<I", len(values)))
    for name, value in sorted(values.items()):
        for index, text in enumerate((name, value)):
            encoded = text.encode("utf-8")
            if index == 1:
                data.append(2)
            data.extend(struct.pack("<I", len(encoded)))
            data.extend(encoded)
    prop(node, "BinaryString", "AttributesSerialize", base64.b64encode(data).decode("ascii"))


def part(parent, name, size, position, color=NAVY, *, cls="Part", transparency=0, collide=True, material=272):
    node = item(parent, cls, name)
    prop(node, "Vector3", "size", size)
    prop(node, "CoordinateFrame", "CFrame", position)
    prop(node, "Color3", "Color", color)
    prop(node, "bool", "Anchored", True)
    prop(node, "bool", "CanCollide", collide)
    prop(node, "bool", "CanTouch", False)
    prop(node, "bool", "CastShadow", transparency < 1)
    prop(node, "float", "Transparency", transparency)
    prop(node, "token", "Material", material)
    prop(node, "token", "TopSurface", 0)
    prop(node, "token", "BottomSurface", 0)
    return node


def label(parent, name, text, size=(1, 0, 1, 0), position=(0, 0, 0, 0), *, color=WHITE, text_size=20, bold=False, align=0, scaled=False):
    node = item(parent, "TextLabel", name)
    prop(node, "UDim2", "Size", size)
    prop(node, "UDim2", "Position", position)
    prop(node, "float", "BackgroundTransparency", 1)
    prop(node, "int", "BorderSizePixel", 0)
    prop(node, "Color3", "TextColor3", color)
    prop(node, "string", "Text", text)
    prop(node, "float", "TextSize", text_size)
    # FontFace avoids legacy Font enum migration limits in current Rojo.
    prop(node, "Font", "FontFace", 700 if bold else 400)
    prop(node, "token", "TextXAlignment", align)
    prop(node, "bool", "TextWrapped", True)
    prop(node, "bool", "TextScaled", scaled)
    prop(node, "bool", "AutoLocalize", False)
    if scaled:
        limits = item(node, "UITextSizeConstraint", "TextBounds")
        prop(limits, "int", "MinTextSize", min(12, text_size))
        prop(limits, "int", "MaxTextSize", text_size)
    return node


def surface(parent, name="Face", face=5, canvas=(1024, 256)):
    node = item(parent, "SurfaceGui", name)
    prop(node, "token", "Face", face)
    prop(node, "Vector2", "CanvasSize", canvas)
    prop(node, "token", "SizingMode", 0)
    prop(node, "float", "LightInfluence", 0)
    prop(node, "float", "MaxDistance", 150)
    prop(node, "bool", "AlwaysOnTop", False)
    return node


def frame(parent, name, size, position=(0, 0, 0, 0), *, color=PANEL, transparency=0):
    node = item(parent, "Frame", name)
    prop(node, "UDim2", "Size", size)
    prop(node, "UDim2", "Position", position)
    prop(node, "Color3", "BackgroundColor3", color)
    prop(node, "float", "BackgroundTransparency", transparency)
    prop(node, "int", "BorderSizePixel", 0)
    return node


def corner(parent, radius=12):
    node = item(parent, "UICorner", "Corner")
    prop(node, "UDim", "CornerRadius", (0, radius))


def button(parent, name, text, size, position=(0, 0, 0, 0), *, color=PANEL, ink=WHITE, text_size=16):
    node = label(parent, name, text, size, position, color=ink, text_size=text_size, bold=True, align=2, scaled=True)
    node.set("class", "TextButton")
    node.find("Properties/float[@name='BackgroundTransparency']").text = "0"
    prop(node, "Color3", "BackgroundColor3", color)
    prop(node, "bool", "AutoButtonColor", True)
    prop(node, "bool", "Selectable", True)
    corner(node, 8)
    return node


def width_bound(node, width, height=1000):
    limit = item(node, "UISizeConstraint", "WidthBounds")
    prop(limit, "Vector2", "MaxSize", (width, height))


def centered(node):
    prop(node, "Vector2", "AnchorPoint", (0.5, 0))
    return node


def model_root():
    return ET.Element("roblox", {"xmlns:xmime": "http://www.w3.org/2005/05/xmlmime", "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance", "version": "4"})


def arena():
    root = model_root()
    world = item(root, "Model", "Arena")
    attrs(world, {"Source": "tools/build_assets.py", "Design": "RuleRoom original primitives; no external assets"})
    tiles = item(world, "Folder", "Tiles")
    for row, z in enumerate(range(-35, 36, 14)):
        for col, x in enumerate(range(-35, 36, 14)):
            color_name, russian, symbol, color = COLORS[(row * 6 + col) % 4]
            tile = part(tiles, f"Tile_{row + 1:02d}_{col + 1:02d}", (14, 2, 14), (x, 0, z), color)
            attrs(tile, {"ColorName": color_name})
            face = surface(tile, "TileLabel", face=1, canvas=(320, 320))
            label(face, "Symbol", symbol, (1, -32, 0.62, 0), (0, 16, 0, 22), color=NAVY, text_size=126, bold=True, align=2)
            label(face, "ColorText", russian, (1, -24, 0.2, 0), (0, 12, 0.72, 0), color=NAVY, text_size=31, bold=True, align=2, scaled=True)
            # Visual-only border belongs to the tile, so it vanishes with the tile.
            outline = frame(face, "EdgeMark", (1, -10, 1, -10), (0, 5, 0, 5), transparency=1)
            stroke = item(outline, "UIStroke", "TileSeam")
            prop(stroke, "Color3", "Color", NAVY)
            prop(stroke, "float", "Thickness", 5)
            prop(stroke, "float", "Transparency", 0.25)

    part(world, "ArenaSpawn", (1, 1, 1), (0, 5, 0), transparency=1, collide=False)
    laser = part(world, "Laser", (84, 1, 1), (0, 2.1, -41.5), COLORS[1][3], transparency=1, collide=False, material=288)
    attrs(laser, {"Purpose": "Server-controlled jump hazard; hidden outside LaserSweep"})

    build_station.build(world, globals())
    return root


def hud():
    root = model_root()
    gui = item(root, "ScreenGui", "RuleRoomHUD")
    prop(gui, "bool", "ResetOnSpawn", False)
    prop(gui, "bool", "IgnoreGuiInset", False)
    prop(gui, "token", "ScreenInsets", 2)
    prop(gui, "bool", "ClipToDeviceSafeArea", True)
    prop(gui, "int", "DisplayOrder", 10)
    prop(gui, "token", "ZIndexBehavior", 1)
    attrs(gui, {"Source": "tools/build_assets.py", "Purpose": "Editable alpha interface; behavior in src/client"})
    content = frame(gui, "Root", (1, 0, 1, 0), transparency=1)
    header = centered(frame(content, "Header", (1, -24, 0, 24), (0.5, 0, 0, 4), transparency=1))
    width_bound(header, 680, 28)
    label(header, "GameTitle", "КОМНАТА / 06", (0.4, 0, 1, 0), text_size=16, bold=True, scaled=True)
    label(header, "PersonalScore", "УР. 1  •  0 МОНЕТ", (0.6, 0, 1, 0), (0.4, 0, 0, 0), color=COLORS[2][3], text_size=15, bold=True, align=1, scaled=True)

    panel = centered(frame(content, "RulePanel", (1, -24, 0, 116), (0.5, 0, 0, 32), transparency=0.04))
    width_bound(panel, 680, 160)
    corner(panel, 10)
    frame(panel, "AccentBar", (0, 4, 1, -20), (0, 0, 0, 10), color=COLORS[0][3])
    column = frame(panel, "TextColumn", (1, -100, 1, 0), (0, 16, 0, 0), transparency=1)
    label(column, "PhaseLabel", "ЛАБОРАТОРИЯ / НАБОР УЧАСТНИКОВ", (1, 0, 0, 16), (0, 0, 0, 8), color=MUTED, text_size=11, bold=True, scaled=True)
    label(column, "RuleLabel", "КОМНАТА ПРОСЫПАЕТСЯ", (1, 0, 0, 29), (0, 0, 0, 26), text_size=25, bold=True, scaled=True)
    label(column, "Instruction", "Читай правило. Двигайся. Попробуй ещё раз!", (1, 0, 0, 32), (0, 0, 0, 57), text_size=17, scaled=True)
    label(column, "RoundLabel", "ЗАБЕГ 1  •  6 ИСПЫТАНИЙ", (1, 0, 0, 16), (0, 0, 1, -21), color=MUTED, text_size=11, scaled=True)
    timer = frame(panel, "Timer", (0, 64, 0, 74), (1, -14, 0.5, 0), color=COLORS[0][3])
    prop(timer, "Vector2", "AnchorPoint", (1, 0.5))
    corner(timer, 8)
    label(timer, "Countdown", "—", (1, -8, 0, 48), (0, 4, 0, 4), color=NAVY, text_size=37, bold=True, align=2, scaled=True)
    label(timer, "UnitLabel", "СЕК", (1, -8, 0, 15), (0, 4, 1, -20), color=NAVY, text_size=10, bold=True, align=2)

    progress = centered(frame(content, "TrialProgress", (1, -28, 0, 4), (0.5, 0, 0, 153), transparency=1))
    width_bound(progress, 672, 6)
    for index in range(6):
        frame(progress, f"Step{index + 1}", (1 / 6, -4, 1, 0), (index / 6, 2, 0, 0), color=(54, 70, 91))
    status = centered(label(content, "PlayerStatus", "Следующее испытание начнётся автоматически", (1, -24, 0, 22), (0.5, 0, 0, 163), text_size=13, bold=True, align=2, scaled=True))
    prop(status, "Color3", "BackgroundColor3", NAVY)
    status.find("Properties/float[@name='BackgroundTransparency']").text = "0.1"
    width_bound(status, 680, 26)
    corner(status, 5)
    health = centered(frame(content, "HealthBar", (0, 160, 0, 4), (0.5, 0, 0, 189), color=(58, 49, 65)))
    frame(health, "Fill", (1, 0, 1, 0), color=COLORS[3][3])
    tip = centered(label(content, "ControlsTip", "WASD — ходьба  •  ПРОБЕЛ — прыжок", (1, -32, 0, 22), (0.5, 0, 0, 199), color=MUTED, text_size=12, align=2, scaled=True))
    prop(tip, "Color3", "TextStrokeColor3", NAVY)
    prop(tip, "float", "TextStrokeTransparency", 0.2)
    width_bound(tip, 680, 28)
    team = centered(frame(content, "TeamPanel", (1, -48, 0, 38), (0.5, 0, 0, 198)))
    width_bound(team, 480, 42)
    corner(team, 6)
    prop(team, "bool", "Visible", False)
    label(team, "ChargeLabel", "ОБЩАЯ ЭНЕРГИЯ  0 / 0", (1, -16, 0, 22), (0, 8, 0, 2), color=COLORS[3][3], text_size=13, bold=True, align=2)
    meter = frame(team, "Meter", (1, -16, 0, 5), (0, 8, 1, -10), color=(48, 65, 78))
    frame(meter, "Fill", (0, 0, 1, 0), color=COLORS[3][3])

    vote = centered(frame(content, "VotePanel", (1, -32, 0, 154), (0.5, 0, 0.48, 0)))
    width_bound(vote, 620, 180)
    corner(vote, 10)
    prop(vote, "bool", "Visible", False)
    label(vote, "Heading", "КАКОЙ БУДЕТ КОМНАТА?", (1, -24, 0, 28), (0, 12, 0, 6), text_size=18, bold=True, align=2, scaled=True)
    row = frame(vote, "Cards", (1, -20, 0, 78), (0, 10, 0, 39), transparency=1)
    for index, mode in enumerate(("Balanced", "Reflex", "Cosmic")):
        button(row, mode, mode, (1 / 3, -6, 1, 0), (index / 3, 3, 0, 0), color=(39, 56, 78), text_size=17)
    label(vote, "Hint", "Один голос • награды одинаковые • можно передумать", (1, -20, 0, 25), (0, 10, 1, -29), color=MUTED, text_size=12, align=2, scaled=True)

    results = centered(frame(content, "ResultsPanel", (1, -36, 0, 148), (0.5, 0, 0.48, 0)))
    width_bound(results, 570, 180)
    corner(results, 10)
    prop(results, "bool", "Visible", False)
    label(results, "Heading", "ЭКСПЕРИМЕНТ ЗАВЕРШЁН", (1, -28, 0, 30), (0, 14, 0, 8), color=COLORS[2][3], text_size=23, bold=True, align=2, scaled=True)
    label(results, "Summary", "", (1, -28, 0, 46), (0, 14, 0, 43), text_size=17, align=2, scaled=True)
    label(results, "Personal", "", (1, -28, 0, 25), (0, 14, 0, 92), color=COLORS[3][3], text_size=16, bold=True, align=2, scaled=True)
    label(results, "Next", "Следующий забег скоро начнётся автоматически", (1, -28, 0, 19), (0, 14, 1, -24), color=MUTED, text_size=12, align=2, scaled=True)

    actions = frame(content, "Actions", (0, 408, 0, 44), (0.5, 0, 1, -12), transparency=1)
    prop(actions, "Vector2", "AnchorPoint", (0.5, 1))
    button(actions, "Collection", "КОСМЕТИКА / ЦЕЛИ", (0, 160, 1, 0), text_size=13)
    button(actions, "Motion", "ЭФФЕКТЫ: ВКЛ", (0, 128, 1, 0), (0, 168, 0, 0), text_size=12)
    button(actions, "Audio", "ЗВУК: ВКЛ", (0, 104, 1, 0), (0, 304, 0, 0), text_size=12)
    spectator = button(content, "SpectateNext", "СЛЕДУЮЩИЙ ИГРОК →", (0, 206, 0, 44), (0.5, 0, 1, -64), text_size=13)
    prop(spectator, "Vector2", "AnchorPoint", (0.5, 1))
    prop(spectator, "bool", "Visible", False)

    backdrop = frame(content, "CollectionBackdrop", (1, 0, 1, 0), color=(0, 0, 0), transparency=0.4)
    prop(backdrop, "bool", "Active", True)
    prop(backdrop, "bool", "Visible", False)
    prop(backdrop, "int", "ZIndex", 3)
    shop = frame(content, "CollectionPanel", (1, -32, 0, 420), (0.5, 0, 0.5, 0), color=NAVY)
    prop(shop, "Vector2", "AnchorPoint", (0.5, 0.5))
    prop(shop, "bool", "Visible", False)
    prop(shop, "bool", "Active", True)
    prop(shop, "int", "ZIndex", 4)
    width_bound(shop, 650, 460)
    corner(shop, 10)
    label(shop, "Heading", "ЛИЧНЫЙ ШКАФЧИК", (1, -74, 0, 36), (0, 16, 0, 5), text_size=21, bold=True, scaled=True)
    button(shop, "Close", "×", (0, 44, 0, 44), (1, -52, 0, 2), text_size=24)
    button(shop, "CosmeticsTab", "СЛЕДЫ", (0.5, -20, 0, 44), (0, 12, 0, 47), text_size=14)
    button(shop, "QuestsTab", "ЗАДАНИЯ", (0.5, -20, 0, 44), (0.5, 8, 0, 47), text_size=14)
    scroll = frame(shop, "Items", (1, -24, 1, -145), (0, 12, 0, 98), transparency=1)
    scroll.set("class", "ScrollingFrame")
    prop(scroll, "UDim2", "CanvasSize", (0, 0, 0, 0))
    prop(scroll, "token", "AutomaticCanvasSize", 2)
    prop(scroll, "int", "ScrollBarThickness", 4)
    prop(scroll, "bool", "ClipsDescendants", True)
    layout = item(scroll, "UIListLayout", "Rows")
    prop(layout, "UDim", "Padding", (0, 7))
    prop(layout, "token", "SortOrder", 2)
    template = frame(shop, "RowTemplate", (1, -8, 0, 66), color=PANEL)
    prop(template, "bool", "Visible", False)
    corner(template, 7)
    swatch = frame(template, "Swatch", (0, 5, 1, -20), (0, 0, 0, 10), color=COLORS[0][3])
    label(template, "Title", "Предмет", (1, -150, 0, 28), (0, 12, 0, 5), text_size=17, bold=True, scaled=True)
    label(template, "Detail", "Описание", (1, -150, 0, 22), (0, 12, 0, 35), color=MUTED, text_size=13, scaled=True)
    button(template, "Action", "ВЫБРАТЬ", (0, 122, 0, 44), (1, -132, 0.5, -22), color=COLORS[0][3], ink=NAVY, text_size=13)
    label(shop, "Message", "Зарабатывай монеты в испытаниях. Следы меняют только внешний вид.", (1, -24, 0, 38), (0, 12, 1, -43), color=MUTED, text_size=12, align=2, scaled=True)
    return root

def station_hud():
    root = model_root()
    gui = item(root, "ScreenGui", "StationHUD")
    prop(gui, "bool", "ResetOnSpawn", False)
    prop(gui, "token", "ScreenInsets", 2)
    prop(gui, "bool", "ClipToDeviceSafeArea", True)
    prop(gui, "int", "DisplayOrder", 9)
    prop(gui, "token", "ZIndexBehavior", 1)
    bar = centered(frame(gui, "StationBar", (1, -24, 0, 104), (0.5, 0, 0, 32)))
    prop(bar, "bool", "Visible", False)
    width_bound(bar, 680, 120)
    corner(bar, 10)
    label(bar, "Status", "ЛАБОРАТОРИЯ / СВОБОДНЫЙ РЕЖИМ", (1, -24, 0, 25), (0, 12, 0, 6), color=COLORS[2][3], text_size=17, bold=True, align=2, scaled=True)
    label(bar, "Detail", "Паркур слева · архив правил справа · галерея впереди", (1, -24, 0, 20), (0, 12, 0, 34), color=MUTED, text_size=13, align=2, scaled=True)
    button(bar, "Join", "В ИСПЫТАНИЯ", (0.5, -18, 0, 44), (0, 12, 0, 59), color=COLORS[2][3], ink=NAVY)
    button(bar, "Explore", "ИССЛЕДОВАТЬ", (0.5, -18, 0, 44), (0.5, 6, 0, 59), color=COLORS[0][3], ink=NAVY)
    # An unobtrusive top-right opt-out remains available while queued in the lobby.
    toggle = button(gui, "ExploreToggle", "ЛАБОРАТОРИЯ", (0, 155, 0, 44), (1, -168, 0, 178), text_size=13)
    prop(toggle, "bool", "Visible", False)
    guide = frame(gui, "Guide", (1, -24, 0, 300), (0.5, 0, 0.5, 0))
    prop(guide, "Vector2", "AnchorPoint", (0.5, 0.5))
    prop(guide, "bool", "Visible", False)
    prop(guide, "bool", "Active", True)
    width_bound(guide, 600, 360)
    corner(guide, 12)
    label(guide, "Heading", "АРХИВ ИСПЫТАНИЙ", (1, -40, 0, 45), (0, 20, 0, 8), color=COLORS[2][3], text_size=23, bold=True, scaled=True)
    close = button(guide, "Close", "ЗАКРЫТЬ", (0, 144, 0, 44), (0.5, 0, 1, -52), color=COLORS[0][3], ink=NAVY)
    prop(close, "Vector2", "AnchorPoint", (0.5, 0))
    label(guide, "Body", "", (1, -40, 1, -125), (0, 20, 0, 60), text_size=20, scaled=True)
    return root


def write_model(path: Path, tree):
    ET.indent(tree, space="  ")
    ET.ElementTree(tree).write(path, encoding="utf-8", xml_declaration=True)
    parsed = ET.parse(path)
    assert parsed.getroot().tag == "roblox"
    return len(parsed.findall(".//Item"))


def main():
    global _ids
    assets = ROOT / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    for filename, factory in (("Arena.rbxmx", arena), ("RuleRoomHUD.rbxmx", hud), ("StationHUD.rbxmx", station_hud)):
        # Referents are local to each XML document. World edits must not renumber every HUD node.
        _ids = itertools.count(1)
        tree = factory()
        path = assets / filename
        count = write_model(path, tree)
        print(f"Built {path.name}: {count} editable instances")


if __name__ == "__main__":
    main()
