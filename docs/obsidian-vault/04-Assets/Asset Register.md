---
project: boblox
updated: 2026-11-08
---

# Реестр ассетов

## Оригинальные схемы и декоративный вариант

Новые 34 детали Atmosphere, два стенда и все 12 учебных схем созданы из собственных примитивов/GUI проекта. Новые следы используют штатный один Trail и 2 Attachments, без текстур внешних авторов. Новые asset IDs, платные материалы и загрузки не добавлены. Авторитетные исходники: build_station.py, GuidePresentation/GuidePreview, EconomyConfig. Реальный импорт/визуальная приёмка не выполнены; план будущих кадров — [MEDIA_PLAN](../../release/MEDIA_PLAN.md).


## Исходники фона и изолированного опыта

Новая последовательность из 8 нот в AudioConfig — оригинальная аранжировка, исполненная прежним встроенным Tone Roblox. Это не новая оригинальная аудиозапись и не право перераспространять файл движка; бинарники/asset IDs не добавлялись. Источники/условия — [AUDIO](../../AUDIO.md).

Сцена изолированного опыта — оригинальные программные Parts/ProximityPrompt/GUI из `prototypes/`, отдельная от Arena.rbxmx. Ни импортированных моделей, ни текстур, ни платных материалов. [Прототипы](../../../prototypes/README.md), [EXPERIENCE_PACKAGE](../../EXPERIENCE_PACKAGE.md). Внешний вид и физика в движке не приняты.


## Дополнения roadmap — 8 ноября 2026

Оригинальные программно созданные детали: A/B/C/D-ориентиры, шесть сегментов и табло реактора (`tools/build_station.py` → `assets/Arena.rbxmx`). Использованы базовые Parts/SurfaceGui и штатные шрифты Roblox, без сторонних моделей/текстур. Манекен примерки и полоски следа создаёт `CollectionPreview`, титулы — `CharacterPresentation`; чужие ассеты не загружаются. Нет новых аудиофайлов/asset IDs. Проверка геометрии/модели локальная; видимость на низкой графике и устройстве ещё не принята.


| Группа | Источник | Авторство / ограничения |
|---|---|---|
| Арена, лобби, декор, 36 плиток | [tools/build_assets.py](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/tools/build_assets.py) → [Arena.rbxmx](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/assets/Arena.rbxmx) | Авторская геометрия из Roblox primitives; без внешнего art-pack |
| HUD и шаблоны панелей | Тот же генератор → [RuleRoomHUD.rbxmx](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/assets/RuleRoomHUD.rbxmx) | Именованные редактируемые UI-объекты; XML генерируется |
| Tone cue | `rbxasset://sounds/volume_slider.ogg` | Встроенный контент Roblox; файл не копируется в репозиторий |
| Impact cue | `rbxasset://sounds/action_jump_land.mp3` | Встроенный контент Roblox; это не оригинальная запись RuleRoom и не CC0 |
| Следы | [EconomyConfig](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/shared/EconomyConfig.luau), [CharacterPresentation](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/client/CharacterPresentation.luau) | Косметические клиентские эффекты без физического преимущества |

Для двух audio-источников сохранены размер, длительность и SHA256 в [AUDIO](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/AUDIO.md). URI встроенного контента не предоставляет отдельной лицензии на перераспространение файла. Никаких выдуманных Creator Store IDs или сторонних пакетов для текущих ассетов не требуется.

Новый ассет должен иметь источник, автора/лицензию, назначение, исходный редактируемый файл, путь импорта и проверку в контексте комнаты. Новые Blender-ассеты сначала проходят этот реестр; сам факт установки Blender не означает наличие игровых моделей.

## Reactor beacon — проверка Blender pipeline

В `assets/source/reactor_beacon/` добавлен оригинальный декоративный маяк: `.blend`, `.fbx`, `.glb`, preview PNG и `manifest.json`. Источник — `tools/blender/build_reactor_beacon.py`; сторонние модели, текстуры и шрифты не использованы. Manifest фиксирует Blender 5.2.2 LTS, 19 mesh objects, 1616 triangles при бюджете 3000 и 4 материала; точные размеры и SHA256 находятся в нём.

Сохранение исходника, экспорт, preview и Blender round trip проверены. **Roblox import NOT RUN**: ориентация, масштаб, материалы, поведение в игре и производительность телефона не приняты. Это ещё не поставляемый игровой ассет. При импорте предполагается декоративное `CanCollide=false`; emission потребуется перенастроить средствами Roblox. Существующая арена не заменена этим примером.

[[05-World-Design/Room]] · [[03-Gameplay-Systems/Presentation]] · [[00-Dashboard/Dashboard]]
