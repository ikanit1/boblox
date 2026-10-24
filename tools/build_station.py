"""Original, editable laboratory complex. No imported assets or runtime geometry."""

COURSE = [(-64, 3, 137), (-73, 5, 126), (-64, 7, 115), (-74, 9, 104),
          (-64, 11, 93), (-74, 13, 82), (-64, 15, 71)]
GUIDES = [
    ("SafeColor", "01 / ЦВЕТ СПАСАЕТ", "Найди цвет и символ.\nОстальной пол исчезнет.", (255, 213, 79)),
    ("LaserSweep", "02 / ПРЫГАЙ ЧЕРЕЗ ЛУЧ", "Жёлтый — подготовка.\nКрасный — прыжок!", (255, 115, 173)),
    ("LowGravity", "03 / ЛУННАЯ КОМНАТА", "Прыгай выше.\nСобирай звёзды ★.", (122, 169, 255)),
    ("RedLight", "04 / ЗАМРИ НА КРАСНЫЙ", "Зелёный — беги.\nКрасный — стой.", (255, 89, 110)),
    ("LavaRise", "05 / ПОЛ — ЭТО ЛАВА", "Запрыгни на платформу.\nНе касайся лавы.", (255, 147, 62)),
    ("MeteorRain", "06 / МЕТЕОРИТНЫЙ ДОЖДЬ", "Красная метка — удар.\nУспей уйти!", (255, 181, 78)),
    ("DisappearingTiles", "07 / ИСЧЕЗАЮЩИЙ ПОЛ", "Уйди с плиток «ПРОВАЛ».\nСледи за каждой волной.", (208, 142, 255)),
    ("SafeZone", "08 / НАЙДИ УБЕЖИЩЕ", "Добеги до зелёной зоны.\nОстанься в ней до сигнала.", (66, 220, 169)),
    ("Spinner", "09 / КРУГОВОЙ ЛУЧ", "Следи за вращением.\nПерепрыгивай луч.", (255, 115, 173)),
    ("ReactorRush", "10 / ЗАРЯДИ РЕАКТОР", "Собирайте заряды вместе.\nДоживите до конца!", (80, 225, 255)),
]


def build(world, api):
    item, prop, part, surface, label, attrs = (api[k] for k in ("item", "prop", "part", "surface", "label", "attrs"))
    navy, steel, panel = (18, 30, 50), (48, 65, 85), (24, 36, 57)
    cyan, gold, white = (80, 225, 255), (255, 213, 79), (232, 243, 255)

    def decor(parent, name, size, position, color=steel, **kw):
        node = part(parent, name, size, position, color, collide=False, **kw)
        prop(node, "bool", "CanQuery", False)
        prop(node, "bool", "CastShadow", False)
        return node

    def board(parent, name, position, size, heading, text, color=cyan, face=2, collide=True):
        p = part(parent, name, size, position, panel, collide=collide)
        s = surface(p, "Display", face=face, canvas=(1000, 500))
        label(s, "Heading", heading, (1, -48, 0.28, 0), (0, 24, 0.06, 0), color=color, text_size=60, bold=True, align=2, scaled=True)
        label(s, "Detail", text, (1, -56, 0.55, 0), (0, 28, 0.36, 0), text_size=40, align=2, scaled=True)
        return p

    def prompt(parent, action, text, title):
        attrs(parent, {"StationAction": action})
        p = item(parent, "ProximityPrompt", "Interact")
        prop(p, "string", "ActionText", text)
        prop(p, "string", "ObjectText", title)
        prop(p, "float", "MaxActivationDistance", 11)
        prop(p, "float", "HoldDuration", 0)
        prop(p, "bool", "RequiresLineOfSight", False)
        return p

    architecture = item(world, "Folder", "Architecture")
    for x in (-43, 43):
        part(architecture, f"SideWall_{x}", (2, 34, 88), (x, 16, 0), navy)
        for z in (-35, -21, -7, 7, 21, 35):
            decor(architecture, f"Rib_{x}_{z}", (0.8, 27, 1.1), (x * 0.973, 14, z))
            decor(architecture, f"Signal_{x}_{z}", (0.18, 7, 0.5), (x * 0.965, 14, z), cyan, material=288)
    part(architecture, "BackWall", (88, 34, 2), (0, 16, -43), navy)
    part(architecture, "ViewingWall", (88, 32, 1), (0, 15, 43), (134, 190, 210), transparency=0.82, material=1568)
    for y in (2, 31):
        decor(architecture, f"WindowFrame_{y}", (88, 0.7, 1.2), (0, y, 43), steel)
    for x in (-42, -21, 21, 42):
        decor(architecture, f"WindowMullion_{x}", (0.6, 32, 1), (x, 15, 43))
    board(architecture, "MainSign", (0, 19, -41.8), (54, 10, 0.5), "RULE ROOM / 06", "КОМНАТА МЕНЯЕТ ПРАВИЛА\n6 ИСПЫТАНИЙ · ОДНА КОМАНДА", gold, collide=False)
    for x in (-32, 32):
        decor(architecture, f"TopBeam_{x}", (2, 2, 88), (x, 33, 0))
        light_panel = decor(architecture, f"ArenaLight_{x}", (8, 0.7, 4), (x, 27, -36), white, material=288)
        light = item(light_panel, "PointLight", "Fill")
        prop(light, "float", "Range", 58)
        prop(light, "float", "Brightness", 1.2)
        prop(light, "Color3", "Color", white)

    lobby = item(world, "Folder", "Lobby")
    attrs(lobby, {"Zone": "Research station / bounds X -90..90, Z 48..192", "Activities": "Practice / rule gallery / cosmetics / viewing deck"})
    part(lobby, "LobbyPlatform", (180, 2, 144), (0, 0, 120), (36, 48, 65))
    # Three connected wings: a wide arrival hall, raised viewing deck, and exhibition aisles.
    for x in range(-80, 81, 20):
        decor(lobby, f"FloorSeamX_{x}", (0.08, 0.03, 144), (x, 1.02, 120), (58, 74, 91))
    for z in range(52, 193, 20):
        decor(lobby, f"FloorSeamZ_{z}", (180, 0.03, 0.08), (0, 1.02, z), (58, 74, 91))
    for x in (-90, 90):
        part(lobby, f"OuterWall_{x}", (2, 22, 144), (x, 10, 120), navy)
        for z in (63, 95, 127, 159, 185):
            part(lobby, f"OuterPillar_{x}_{z}", (3, 26, 3), (x, 12, z), steel)
            decor(lobby, f"PillarLight_{x}_{z}", (0.25, 12, 0.5), (x * 0.982, 10, z), cyan, material=288)
    part(lobby, "RearWall", (180, 22, 2), (0, 10, 192), navy)
    # Side boundaries of the viewing deck are closed; the arena void stays unobstructed.
    for x in (-67, 67):
        part(lobby, f"GalleryFront_{x}", (46, 5, 1), (x, 2, 48), steel)
    part(lobby, "GalleryBridge", (88, 2, 6), (0, 0, 45), (36, 48, 65))
    for x in (-44, 44):
        part(lobby, f"BridgeRail_{x}", (1, 6, 8), (x, 3, 45), steel)
    # Low platform steps leave the central view unobstructed and can be walked up.
    for i in range(3):
        part(lobby, f"ViewingStep_{i}", (82, 0.6 * (i + 1), 4), (0, 1 + 0.3 * (i + 1), 65 - i * 4), steel)
    decor(lobby, "GalleryEdge", (84, 0.12, 0.5), (0, 2.85, 54), gold, material=288)
    board(lobby, "GalleryTitle", (0, 16, 45), (34, 4.5, 0.7), "СМОТРОВАЯ ГАЛЕРЕЯ", "НАБЛЮДАЙ · ЗАПОМИНАЙ · ПРОБУЙ СНОВА", gold)

    # Arrival wayfinding and a central reactor sculpture, with free paths on both sides.
    spawn = part(world, "LobbySpawn", (8, 1, 8), (0, 4, 158), cyan, cls="SpawnLocation", transparency=1, collide=False)
    prop(spawn, "bool", "Neutral", True)
    prop(spawn, "float", "Duration", 0)
    prop(spawn, "bool", "Enabled", True)
    decor(lobby, "ArrivalPad", (16, 0.1, 12), (0, 1.07, 158), (46, 92, 109))
    for x in (-13, 13):
        decor(lobby, f"Path_{x}", (0.35, 0.1, 99), (x, 1.08, 109), cyan, material=288)
    for z in (143, 134, 125, 116, 107, 98, 89, 80):
        decor(lobby, f"Wayfinder_{z}", (3.5, 0.1, 0.6), (0, 1.1, z), gold, material=288)
    board(lobby, "Welcome", (0, 14, 190.7), (64, 12, 0.5), "ЛАБОРАТОРИЯ ПРАВИЛ", "ВПЕРЁД — ИСПЫТАНИЯ\nСЛЕВА — ПАРКУР  /  СПРАВА — СЕКРЕТЫ ПРАВИЛ", gold, face=5)
    for x, heading, text in ((-42, "ТРЕНИРОВОЧНЫЙ КОНТУР", "7 ПРЫЖКОВ · ЛИЧНЫЙ РЕКОРД"), (42, "АРХИВ ИСПЫТАНИЙ", "10 ПРАВИЛ · ПОДСКАЗКИ БЕЗ РИСКА")):
        board(lobby, f"WingSign_{x}", (x, 12, 172), (38, 7, 0.8), heading, text)
        part(lobby, f"WingPost_{x}", (1, 11, 1), (x, 6, 172), steel)

    reactor = item(lobby, "Folder", "ReactorExhibit")
    part(reactor, "Plinth", (17, 2, 17), (0, 2, 177), steel)
    part(reactor, "Base", (11, 2, 11), (0, 4, 177), navy)
    core = decor(reactor, "EnergyCore", (6, 9, 6), (0, 11, 177), cyan, material=288)
    prop(core, "token", "Shape", 0)
    for y in (6, 16):
        for axis in (0, 1):
            decor(reactor, f"Containment_{y}_{axis}", (12, 0.7, 2) if axis == 0 else (2, 0.7, 12), (0, y, 177), gold)
    for x in (-5, 5):
        for z in (-5, 5):
            part(reactor, f"Frame_{x}_{z}", (1, 14, 1), (x, 10, 177 + z), steel)
    board(lobby, "HowToPlayBoard", (0, 6, 166.5), (21, 7, 0.8), "ТВОЯ ЗАДАЧА", "Пройди 4 из 6 испытаний.\nВыживи в заряженном финале.\nВыбыл? Следующая попытка скоро.", gold, face=5)

    # Queue console is genuinely interactive; the arch frames the viewing deck, not a fake teleport.
    part(lobby, "EntryArchTop", (35, 2.5, 3), (0, 14, 73), steel)
    for x in (-17, 17):
        part(lobby, f"EntryArchLeg_{x}", (2, 14, 3), (x, 7, 73), steel)
        decor(lobby, f"EntryArchLight_{x}", (0.3, 10, 0.4), (x + (1.1 if x < 0 else -1.1), 7, 74.6), gold, material=288)
    queue = board(lobby, "QueueConsole", (0, 3.3, 76), (9, 4.6, 2), "В ИСПЫТАНИЯ", "Вход со следующего старта", gold)
    prompt(queue, "Join", "Встать в очередь", "ИСПЫТАНИЯ / 06")
    explore = board(lobby, "ExploreConsole", (23, 3.3, 149), (9, 4.6, 2), "ИССЛЕДОВАТЬ", "Остаться в лаборатории", cyan, face=5)
    prompt(explore, "Explore", "Остаться здесь", "ЛАБОРАТОРИЯ")

    practice = item(lobby, "Folder", "Practice")
    attrs(practice, {"Purpose": "Optional ordered server-timed course; session record only; no currency"})
    part(practice, "StartPad", (10, 1, 10), (-64, 1.6, 150), (44, 116, 119))
    start = board(practice, "StartConsole", (-51, 3.5, 153), (8, 5, 2), "ПАРКУР / 07", "Стартуй и побей свой рекорд!", cyan, face=5)
    prompt(start, "Practice", "Начать / заново", "ТРЕНИРОВОЧНЫЙ КОНТУР")
    for i, (x, y, z) in enumerate(COURSE, 1):
        block = part(practice, f"Checkpoint{i}", (12, 1, 12), (x, y, z), (52, 105, 119) if i < 7 else gold)
        attrs(block, {"Checkpoint": str(i)})
        decor(practice, f"Support{i}", (2, y - 1, 2), (x, (y + 1) / 2, z), steel)
        decor(practice, f"Edge{i}", (12, 0.12, 0.35), (x, y + 0.56, z + 5.7), cyan if i < 7 else gold, material=288)
        s = surface(block, "Number", face=1, canvas=(320, 320))
        label(s, "Index", f"{i:02d}" if i < 7 else "ФИНИШ", text_size=110 if i < 7 else 62, bold=True, align=2, scaled=True)
    board(practice, "FinishSign", (-64, 22, 65), (20, 5, 0.7), "07 / ФИНИШ", "Рекорд считается на сервере", gold)
    for i, z in enumerate((150, 133, 116, 99, 82, 65)):
        decor(practice, f"CourseLane{i}", (0.25, 0.08, 12), (-83, 1.07, z), cyan, material=288)

    gallery = item(lobby, "Folder", "RuleGallery")
    for i, (rule_id, heading, text, color) in enumerate(GUIDES):
        x, z = (41 if i % 2 == 0 else 70), 145 - (i // 2) * 18
        stand = board(gallery, rule_id, (x, 5.2, z), (22, 8, 1), heading, text, color)
        part(gallery, f"Foot_{i}", (23, 1, 5), (x, 1.5, z), steel)
        decor(gallery, f"Header_{i}", (22, 0.2, 1.1), (x, 9.35, z), color, material=288)
        prompt(stand, "Guide:" + rule_id, "Узнать правило", heading)
        # Small original dioramas explain the silhouettes before players ever enter a trial.
        icon = item(gallery, "Folder", f"Exhibit_{rule_id}")
        decor(icon, "Shelf", (13, 0.5, 6), (x, 10.1, z), steel)
        if rule_id in ("SafeColor", "DisappearingTiles", "SafeZone"):
            for j in range(4):
                tile_color = ((70, 168, 244), (255, 115, 173), gold, (66, 220, 169))[j] if rule_id == "SafeColor" else ((66, 220, 169) if j == 2 else steel)
                decor(icon, f"Tile{j}", (4, 0.6, 2), (x - 2.2 + (j % 2) * 4.4, 10.8 + (1 if rule_id == "DisappearingTiles" and j % 2 else 0), z - 1.1 + (j // 2) * 2.2), tile_color)
        elif rule_id in ("LaserSweep", "Spinner"):
            decor(icon, "Beam", (12, 0.35, 0.35), (x, 12, z), color, material=288)
            for side in (-1, 1):
                decor(icon, f"Emitter{side}", (1.4, 3, 2), (x + side * 6, 11.5, z), steel)
            if rule_id == "Spinner":
                decor(icon, "CrossBeam", (0.35, 0.35, 5), (x, 12, z), color, material=288)
        elif rule_id == "RedLight":
            for j, c in enumerate(((66, 220, 169), gold, (255, 89, 110))):
                ball = decor(icon, f"Signal{j}", (2.3, 2.3, 2.3), (x - 4 + j * 4, 12, z), c, material=288)
                prop(ball, "token", "Shape", 0)
        elif rule_id == "LavaRise":
            decor(icon, "Lava", (11, 0.4, 4), (x, 10.7, z), (255, 147, 62), material=288)
            for j in (-1, 1):
                decor(icon, f"Island{j}", (3, 2, 3), (x + j * 3, 11.4, z), (70, 168, 244))
        else:
            for j in range(3):
                ball = decor(icon, f"Particle{j}", (1.6 + j * 0.3,) * 3, (x - 4 + j * 4, 12 + (j % 2) * 2, z), color, material=288)
                prop(ball, "token", "Shape", 0)

    showroom = item(lobby, "Folder", "Showroom")
    for i, (name, color) in enumerate((("ЛАЗУРЬ", (70, 168, 244)), ("РОЗОВЫЙ", (255, 115, 173)), ("ЗОЛОТО", gold), ("МЯТА", (66, 220, 169)))):
        x = 38 + i * 12
        part(showroom, f"Plinth{i}", (8, 2, 8), (x, 2, 178), steel)
        for j in range(4):
            decor(showroom, f"Trail_{i}_{j}", (1.6, 1.6, 1.6), (x - 2 + j * 1.2, 4 + j * 0.75, 178), color, material=288)
    cosmetic = board(showroom, "Wardrobe", (55, 4, 165), (20, 6, 1), "ЛИЧНЫЙ ШКАФЧИК", "Следы и задания · за монеты в игре", cyan, face=5)
    prompt(cosmetic, "Collection", "Открыть шкафчик", "СЛЕДЫ И ЗАДАНИЯ")
    scores = board(lobby, "SessionBoard", (-38, 7, 183), (26, 10, 1), "ОЧКИ ТЕКУЩЕГО ЗАБЕГА", "Здесь появятся результаты игроков", gold, face=5)
    attrs(scores, {"Purpose": "Live server scores; no invented player counts"})
    for x in (-38, 26):
        for z in (91, 122):
            part(lobby, f"Bench_{x}_{z}", (6, 1.5, 13), (x, 2.2, z), steel)
    research = item(lobby, "Folder", "ResearchEquipment")
    for i, (x, z) in enumerate(((-35, 145), (-35, 110), (-35, 76))):
        part(research, f"Desk{i}", (13, 3, 7), (x, 2.5, z), navy)
        decor(research, f"DeskTrim{i}", (13, 0.2, 7.1), (x, 4.1, z), steel)
        screen = board(research, f"Monitor{i}", (x, 6.2, z - 1), (10, 4, 0.5), ("СИГНАЛ КОМНАТЫ", "ПРОТОКОЛ ВЫЖИВАНИЯ", "ЭНЕРГИЯ КОМАНДЫ")[i], ("ПРАВИЛА МЕНЯЮТСЯ", "СМОТРИ НА ПРЕДУПРЕЖДЕНИЯ", "ЗАРЯЖАЙТЕ РЕАКТОР ВМЕСТЕ")[i], cyan)
        for j in range(4):
            decor(research, f"Key{i}_{j}", (0.8, 0.15, 0.8), (x - 3 + j * 2, 4.3, z + 2), cyan if j % 2 else gold, material=288)
        for j in (-1, 1):
            decor(research, f"EquipmentCase{i}_{j}", (3, 4, 4), (x + 9, 3, z + j * 3), steel)
    # Planters, vents and cable runs break up long walls without affecting the arena.
    for i, (x, z) in enumerate(((-22, 162), (22, 162), (-22, 83), (22, 83), (-82, 176), (84, 158))):
        part(lobby, f"Planter{i}", (4, 2.5, 4), (x, 2.25, z), steel)
        for j in (-1, 0, 1):
            leaf = decor(lobby, f"Plant{i}_{j}", (2.1, 4 + abs(j), 1.6), (x + j * 0.8, 5, z + j * 0.5), (42, 133 + j * 12, 113))
            prop(leaf, "token", "Shape", 0)
    for side in (-1, 1):
        for i in range(3):
            decor(lobby, f"Cable_{side}_{i}", (0.65, 0.65, 135), (side * 88.2, 13 + i * 1.4, 120), (64, 86, 102))
        for z in (112, 172):
            decor(lobby, f"Vent_{side}_{z}", (0.6, 5, 12), (side * 88.5, 6, z), steel)
            for y in (4.5, 5.5, 6.5, 7.5):
                decor(lobby, f"VentSlat_{side}_{z}_{y}", (0.7, 0.2, 10), (side * 88.1, y, z), navy)
    for x in (-27, 27):
        for z in (88, 150):
            lamp = decor(lobby, f"HubLamp_{x}_{z}", (4, 0.5, 4), (x, 21, z), white, material=288)
            light = item(lamp, "PointLight", "Fill")
            prop(light, "float", "Range", 46)
            prop(light, "float", "Brightness", 0.7)
    # Silhouette structures beyond the playable boundaries add scale without walkable exploits.
    skyline = item(world, "Folder", "Background")
    for i, (x, z, h) in enumerate(((-115, 55, 48), (112, 75, 65), (-120, 160, 36), (118, 180, 44), (-58, 220, 64), (50, 230, 75))):
        decor(skyline, f"Tower_{i}", (18, h, 24), (x, h / 2 - 3, z), (30, 43, 61))
        decor(skyline, f"TowerBand_{i}", (18.3, 0.7, 24.3), (x, h - 7, z), (63, 130, 155), material=288)
