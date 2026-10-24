---
project: boblox
updated: 2026-10-24
---

# Skills и маршрутизация

Установлены 82 навыка трёх запрошенных библиотек: EL4CTEO 23 (`el4-`), Roblox Brain 29 (`brain-`), Blender 30 (`ccb-`). Два проектных координирующих навыка установлены отдельно. Реальный Codex `skills/list` подтвердил 84/84 уникальных имени, enabled, без ошибок. Совпадающие оригинальные имена не перезаписывались; ресурсы и MIT-лицензии сохранены.

Машинный каталог в репозитории: `docs/environment/skills-catalog.json`; читаемый каталог: `docs/environment/skills-catalog.md`. В них указаны источник, commit, точный путь установки, назначение, условия выбора, требуемые инструменты и ограничения. `skills-discovery.json` и `skills-validation.json` содержат проверенные уровни свидетельств. Каталог не копируется в эту заметку.

## В начале задачи

1. Прочитать корневой AGENTS.md и [[00-Dashboard/Dashboard]], проверить Git remote/branch/dirty files.
2. Прочитать установленный `router` и проектный `roblox-development-orchestrator` из `.agents/skills/`.
3. Выбрать минимальные навыки по задаче и прочитать нужные references. Не загружать все 82 инструкции.
4. Выполнить проверки соответствующего уровня и обновить затронутые знания через `obsidian-gamedev-workflow`.

| Работа | Найти в каталоге |
|---|---|
| Механика | game-design, game-systems, architecture, Luau, testing |
| Мультиплеер | networking, security, architecture, testing |
| Интерфейс | GUI/UI, input, player-psychology |
| Данные | data-stores/server-data, security, testing |
| Комната/модель | world-building/building, lighting, performance, Blender modeling/export |
| Оптимизация | performance, code-review, tooling |
| Выпуск | publish checklist, testing, analytics/security в пределах разрешения пользователя |

Маршрутизация — рабочее правило, а не доказательство выполнения всех рецептов. Проверены frontmatter, ресурсы, синтаксис bundled Python и обнаружение Codex. 225 bundled eval-сценариев проверены как данные; модели на них не запускались. У двух отсутствующих upstream references Blender есть явно помеченные redirects к существующим разделам того же источника. Исторический отсутствующий log не подменён выдуманным свидетельством.

## Воспроизводимость

Из корня репозитория: `python tools/skills/install_libraries.py --mode install`, затем `python tools/skills/verify_discovery.py`. Для двух координаторов: `python tools/environment/install_project_skills.py`. Установщики проверяют владение и отказываются перетирать чужие или изменённые навыки. Новые метаданные доступны Codex в следующем ходе/сессии; значимые рецепты проверяются при их реальном использовании.

Инструменты и навыки не заменяют результаты [[06-Testing/Verification]]. Работа Studio MCP, Blender MCP, Obsidian CLI и файловой интеграции проверяется отдельно. Глобальные навыки координации активируются для проекта с соответствующим AGENTS.md; правила RuleRoom не распространяются на посторонние репозитории.

[[08-Decisions/Decisions]] · [[07-Tasks/Working Board]] · [[00-Dashboard/Dashboard]]
