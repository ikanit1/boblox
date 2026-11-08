---
project: boblox
updated: 2026-11-08
---

# Где менять код

## Интегрированные дополнения

- Server: TraversalMath + ArenaRules — новые опасности и финал со стабилизацией; ProfileService — RetryLoad, ProfileData — v5/серверные косметические unlock.
- Client/shared: GuidePreview/GuidePresentation — обучение; RoomThemes + RoomDisplay — декоративные варианты; EconomyConfig/Collection — состояния и примерка восьми следов.
- Tools: validate_performance.py — проверка выгрузок; package_candidate.py — ZIP проверенного кандидата; единственный generator заменяет повторное XML-свойство.
- Журнал реализации и текущей проверки: [PRODUCT_COMPLETION](../../PRODUCT_COMPLETION.md).


## Следующий пакет: новые границы

`shared/PlayerPreferences` — allowlist/defaults/нормализация. `client/AudioPreferences` — локальный выбор и ограниченная очередь подтверждения, `AudioSettings` — панель; AudioController владеет только звуком. CharacterPresentation сохраняет владение камерой/титулами и добавляет SpectatorPicker.

`prototypes/` изолирован через `prototypes.project.json`: ExperimentMath, ExperimentSession, Experiments.server, ExperimentHUD.client. Этот путь не маппируется в default.project.json и не запускает основные ProfileService/Main. Build создаёт `RuleRoomExperiments.rbxlx` отдельно; candidate manifest проверяет его Source/изоляцию. [EXPERIENCE_PACKAGE](../../EXPERIENCE_PACKAGE.md).


## Дополнение roadmap-пакета — 8 ноября 2026

- `server/ContributionLedger` хранит ограниченный социальный вклад, `shared/ContributionView` проверяет снимок, `client/TeamResults` показывает страницы внутри Results. Награды остаются у Roster/ProfileService.
- `server/RuleAvailability` проверяет серверные флаги; RuleDeck выбирает допустимую последовательность, Main управляет ожиданием. Клиентского remote для флагов нет.
- `server/AnalyticsSession` отделяет намерение повтора от авто-допуска; Analytics.server владеет ограниченной доставкой.
- `client/CollectionPreview` владеет одним ViewportFrame; CharacterPresentation — лобби-титулами; LunarPickups — частной видимостью звёзд.
- `shared/RoomDisplay` и `client/RoomDisplay` оформляют табло, не определяют результат.
- `shared/BoundedMetrics` и немаппируемый `tools/studio/performance_probe.luau` подготавливают измерения. `tools/candidate_manifest.py` связывает Build с реальными входами/местом; не заявляет native-приёмку.

Контракты: [ALPHA_CONTRACT](../../ALPHA_CONTRACT.md). Общая проверка: [ROADMAP_PROGRESS](../../ROADMAP_PROGRESS.md).


Таблица указывает реальные пути репозитория. Внешние ссылки на код закреплены за исходным `afdbc08`, чтобы Obsidian не пытался искать файлы за границами vault как отсутствующие заметки. Перед правкой открывайте соответствующий локальный файл текущего checkout; ссылка на baseline не показывает незакоммиченные изменения.

| Путь | Ответственность |
|---|---|
| [Main.server](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/server/Main.server.luau) | Голосование, фазы, колода, итоги и завершение забега |
| [PlayerRoster](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/server/PlayerRoster.luau) | Допуск, смерть, возрождение, once-per-trial награды и движение |
| [ArenaRules](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/server/ArenaRules.luau), [RuleMath](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/server/RuleMath.luau) | Опасности, сбор, геометрия и cleanup |
| [ProfileService](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/server/ProfileService.luau), [ProfileData](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/server/ProfileData.luau) | Жизненный цикл профиля и чистые операции данных |
| [EconomyConfig](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/shared/EconomyConfig.luau) | Награды, каталог, задания и opt-in облака |
| [GameConfig](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/shared/GameConfig.luau), [RuleDeck](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/shared/RuleDeck.luau) | Правила, отображаемые данные и воспроизводимый выбор |
| [HUD](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/client/HUD.client.luau), [CollectionPanel](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/client/CollectionPanel.luau) | Текст, таймер, голосование, коллекция и задания |
| [CharacterPresentation](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/client/CharacterPresentation.luau) | Наблюдение, камера и следы |
| [AudioController](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/client/AudioController.luau), [AudioConfig](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/shared/AudioConfig.luau) | Локальные ограниченные звуковые сигналы |
| [Analytics.server](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/server/Analytics.server.luau) | Серверная воронка; доставка в Studio отключена |
| [build_assets.py](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/tools/build_assets.py) | Авторский источник комнаты и HUD |
| [default.project.json](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/default.project.json) | Размещение исходников Rojo в DataModel |
| [Build.ps1](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/Build.ps1) | Генерация, format/lint/compile, тесты и проверка модели |

Перед работой назначить агентам непересекающиеся файлы. Только один оператор управляет конкретной Studio-сессией. Проверить branch/HEAD и выбранное место: построенный файл и открытое окно не всегда соответствуют друг другу.

Из корня: `powershell -ExecutionPolicy Bypass -File .\Build.ps1`. Rojo `Serve.ps1` слушает 127.0.0.1:34872; плагин Studio нужно явно подключить. [AGENTS](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/AGENTS.md) и контракт имеют приоритет над общими навыками.

[[02-Architecture/Architecture]] · [[09-AI-Skills/Index]] · [[00-Dashboard/Dashboard]]
