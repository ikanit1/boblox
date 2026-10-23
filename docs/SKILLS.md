# Навыки и инструменты агентов

Аудит 23 октября 2026. Полезный комплект покрывает задачи проекта; найти буквально все существующие skills в интернете невозможно. Навык — инструкция, MCP — доступ к Studio, CLI — исполняемая проверка. Наличие любого из них не доказывает работоспособность игры.

## Установленный основной комплект

Источник: [awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills), локальный commit `d4b0e35550c55ae70bdfcab4ef5a0e94610438a9`. Папка `%USERPROFILE%/.agents/skills/`.

| Работа | Подключаемые skills |
|---|---|
| Выбор подхода | router один раз, затем только нужные навыки |
| Luau / Studio / структура | roblox-luau, roblox-studio-workflow |
| Сетевые запросы и защита | roblox-networking |
| Персонажи / физика | roblox-characters, roblox-physics |
| Данные и восстановление | roblox-datastores, save-systems |
| HUD / телефон / камера | roblox-ui, game-ui-ux, input-systems, camera-systems |
| Уровни / ощущение игры | level-design, game-feel, procedural-gen |
| Ассеты / звук / производительность | create-game-assets, audio-design, performance-optimization |

## Добавлено в этом задании

Через системный skill-installer установлены **roblox-audio**, **roblox-vfx**, **roblox-testing** из [nonlooped/roblox-suite](https://github.com/nonlooped/roblox-suite/tree/996cae9629bee59841bf057f9826750620ed80bf), commit `996cae9629bee59841bf057f9826750620ed80bf`, в `%USERPROFILE%/.codex/skills/`. Существующие навыки не заменялись. Примеры — справочный код, а не встроенная зависимость игры; API и разрешения ассетов проверяются по текущей документации Roblox. Автоматически выполняемых установочных скриптов этой коллекции не запускали.

Для новой машины: прочитать skill-installer, установить три названные папки из закреплённого commit. Не устанавливать всю коллекцию только ради числа навыков; одноимённые UI/networking/datastore инструкции могут конфликтовать.

## Официальная Studio

[Roblox/roblox-studio-agent-plugin](https://github.com/Roblox/roblox-studio-agent-plugin) 0.2.2, commit `0ae5b1105f82748946d0b35ea168482e470647a7`, уже установлен. Подключение через [официальный MCP](https://create.roblox.com/docs/studio/mcp). Setup skill живёт в плагине, рабочие инструкции предоставляет Studio через `skill`.

Подтверждённый каталог в текущей версии: rbx-debug, rbx-device-simulator-lua, rbx-docs-search, rbx-perf-profiling, rbx-scene-analysis, rbx-unit-test, rbx-create-skill. Перепроверять tools/list после обновления Studio. Одновременно сценой управляет один агент, остальные меняют назначенные файлы.

## Найдено, но не установлено целиком

| Коллекция | Проверенная версия | Использовать при необходимости |
|---|---|---|
| [afrxo/roblox-agent-skills](https://github.com/afrxo/roblox-agent-skills) | ff50be7a8a000a24c0f85254e1747a0eb35d857f | luau-expert, roblox-toolchain; UI дублируется, Fusion не вводим по одному примеру |
| [m4bwav/roblox-agent](https://github.com/m4bwav/roblox-agent) | 581a33a065ad28d17037ac65a9c1376decea25f4 | проверки, CI и Open Cloud; скрипты сначала читать |
| [TabooHarmony/roblox-brain](https://github.com/TabooHarmony/roblox-brain) | ceee4aaa5004502e2a51d78b3c33bba44d84742b | структура дизайна/аналитики/локализации; советы о ранжировании и монетизации перепроверять по первичным источникам |

Платежи потребуют отдельно roblox-gamepasses и официальной документации [Developer Products](https://create.roblox.com/docs/production/monetization/developer-products); одних инструкций недостаточно для идемпотентной выдачи покупок.

## Практический процесс

Дизайн и контракт → отдельные владельцы gameplay/presentation/profile → статическая сборка и чистые тесты → один агент проверяет живую Studio → два клиента и телефон → внешняя проверка интереса → ограниченный опубликованный тест. После каждого содержательного изменения сохранять исходники в boblox.

Rojo, Luau, StyLua, Selene и Lune установлены; версии и SHA256 — toolchain.json. `luau-compile` проверяет синтаксис, а обычный `luau-analyze` чистую логику. Полная проверка движковых типов требует Studio либо [Luau LSP](https://github.com/JohnnyMorganz/luau-lsp) с Roblox definitions и sourcemap; пока нельзя называть компиляцию полной типизацией.
