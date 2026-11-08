# План для Codex — завершение второго пакета RuleRoom

Дата: 2026-11-08. Исполнитель: **Codex, вся оставшаяся работа**. Claude больше не редактирует файлы этого checkout; ограничения владения из прошлых брифов сняты — Codex может менять любые файлы, нужные для пунктов ниже.

Ветка: `feat/readable-fair-first-session`, база `08ba71e`. Всё — незакоммиченное рабочее дерево (≈38 файлов). **Без commit/push**, без публикации в Roblox, без Robux и платных ассетов (AGENTS.md).

Перед началом прочитать: `AGENTS.md`, `docs/obsidian-vault/00-Dashboard/Dashboard.md`, `docs/ALPHA_CONTRACT.md`, `docs/SECOND_PACKAGE.md` (черновик отчёта этого пакета), `.agents/skills/roblox-development-orchestrator/SKILL.md`.

> **Результат выполнения, 2026-11-08.** Пункты **1–5 завершены**: серверный Forfeited/рекорды, согласование клиента, итоговый review и исправления, документация, полная Build.ps1 и отдельный прогон всех 15 тестовых наборов через Lune. Точные результаты и оставшиеся ограничения — [SECOND_PACKAGE](SECOND_PACKAGE.md). Пункт 6 **не запускался**: MCP вернул `studios: []`; он условный и не закрывает native-приёмку. Раздел 0 ниже — историческое состояние передачи, не текущий список незавершённых правок. Ничего не закоммичено, не отправлено в GitHub и не опубликовано в Roblox; нового SHA-манифеста нет.

---

## 0. Состояние на момент передачи (03:26)

### Уже сделано и проверено локально (не переделывать)

Клиент (Claude), всё на атрибутах контракта, работает без них:

| Что | Где |
|---|---|
| Строка «⚠ Движение не подтверждено — награда этапа снята» при `MovementWarning` в компактной панели (64 px, под таймером, тост ниже) и второй строкой статуса на ПК | `src/client/HUD.client.luau` (`applyCompactPlay`, `renderStatus`), текст `PlayerHints.MovementWarning` |
| Исход `Forfeited`: символ «!» на жёлтом в полоске этапов и итогах; строка «! Этап N: жив, награда снята» в `Results.Personal`; тост «! ЖИВ · НАГРАДА ЭТАПА СНЯТА»; тост «+монеты» за такой этап подавлен; звук `Forfeited`; поздний вход считает Forfeited участием | `HUD.client.luau` (`outcomeVisuals`, `queuedLateEntry`, `renderPlayer`), `RunFeedback.luau`, `AudioController.luau`, `AudioConfig.luau`, `PlayerHints.Forfeited`/`forfeitedLine` |
| «НОВЫЙ РЕКОРД: 340 очков · 5 / 6 этапов» в `Results.Rewards` по `NewRecord` | `HUD.client.luau`, `PlayerHints.newRecordLine` |
| Блок «Рекорды и мастерство» во вкладке «Задания» шкафчика (внутри прокручиваемого `Items`; фокус геймпада на 1-м задании прокручивает к началу) | `CollectionPanel.luau`, `PlayerHints.masterySummary`/`flawlessCount` |
| Звук `WarningFinal` (последняя секунда Warning, 3 нарастающие ноты) и `Safe` (переход в Recovery); mute; `ReducedNotes` при `ReducedMotion` | `AudioController.luau`, `AudioConfig.luau` |
| Кнопка «ПОЗВАТЬ ДРУЗЕЙ» в `StationHUD.StationBar.Invite` (генератор), `CanSendGameInviteAsync`/`PromptGameInvite` в pcall, скрыта если нельзя, страховочный сброс 15 с | `tools/build_assets.py`, `assets/StationHUD.rbxmx`, `Station.client.luau` |
| Текст панели лаборатории «Твой рекорд паркура: %.2f сек» (без «до выхода с сервера») | `Station.client.luau` |
| Тесты текстов: 136 проверок | `tests/PlayerHints.spec.luau` |

Сервер (Codex, предыдущий проход): ProfileData schema v2, рекорды/практика/Flawless, NewRecord, lease/shutdown, правила (категории колоды, RedLight, LowGravity, LaserSweep 40, LavaRise, DisappearingTiles, SafeZone), мягкая проверка движения. Описано в `ALPHA_CONTRACT.md` → Progression API.

Документы, уже обновлённые черновиком: `docs/SECOND_PACKAGE.md`, `docs/AUDIO.md`, `Roadmap.md` (раздел «Второй пакет»), `Dashboard.md`, `Evidence Index.md`, `05-World-Design/Room.md`.

### В процессе (phase0-records-forfeit) — не завершено

- `tests/PlayerRoster.integration.luau` и `tests/RunPresentation.spec.luau` уже ожидают `Forfeited` (строки ≈336–410 и 20).
- `src/shared/RunPresentation.luau:32–39` уже учитывает `Forfeited` как допуск.
- **Нет** публикации `TrialOutcome_N = "Forfeited"` / `LastTrialOutcome = "Forfeited"` в `src/server/PlayerRoster.luau` (там только флаг `rewardForfeited`).
- **Нет** упоминания `Forfeited` в `docs/ALPHA_CONTRACT.md`.
- `Main.server.luau:268–269`: строка `FinaleSuccess` — менять только её.

---

## 1. Завершить phase0-records-forfeit (сервер)

Файлы: `src/server/PlayerRoster.luau`, `src/shared/RunPresentation.luau`, `src/server/Main.server.luau` (только FinaleSuccess), `src/server/RuleMath.luau`, при необходимости `ProfileService.luau`, `ProfileData.luau`, `Station.server.luau`, `EconomyConfig.luau`; тесты.

1. `PlayerRoster.AwardSurvivors(ruleId)` → возвращает `(awarded, forfeitedAlive)`. Выживший с `entry.rewardForfeited` или `MovementWarning == true`:
   - `TrialOutcome_<index> = "Forfeited"`, `LastTrialOutcome = "Forfeited"`;
   - **не** увеличивает `RunSurvived` и внутренний `record.survived`, не вызывает `AwardSurvival`, не даёт очков/монет/XP, не вызывает `RecordFlawless`;
   - `EndRound` сохраняет `Forfeited` (не превращает в Survived/Skipped).
   - Завершение испытания без награды (отмена/таймаут) для предупреждённого выжившего тоже публикует `Forfeited`.
2. Финал: Forfeited на ReactorRush **не** засчитывается как «пережил финал» — личной победы быть не может (`RunPresentation.spec:20`). Проверить `RuleMath.runOutcome`/`RunPresentation.resultCode`.
3. `Main.server.luau:268`: `FinaleSuccess` = заряд достигнут **и** есть хотя бы один выживший с наградой (`awarded > 0`); Forfeited-выжившие успех команды не дают. Если тест требует иное — следовать тесту и записать решение в контракт.
4. `MovementWarning` сбрасывается в `StartRound`, при выбывании и в начале нового испытания (уже есть — не сломать).
5. `ALPHA_CONTRACT.md`: в Progression API / разделе исходов описать `"Forfeited"` (значение `TrialOutcome_N`/`LastTrialOutcome`; жив, награда снята; не влияет на RunSurvived, награды, Flawless, личную победу; учитывается как участие для позднего входа), и итоговое правило `FinaleSuccess`.
6. Прогнать `PlayerRoster.integration`, `RunPresentation.spec`, `ArenaRules.integration`, `ProfileService.integration`, `RuleMath.spec` — все зелёные.

Приёмка: тесты из пункта 0 проходят без правок их ожиданий (кроме явных ошибок — тогда объяснить в отчёте).

## 2. Сверить клиент с итоговым сервером

1. `git diff src/client src/shared/PlayerHints.luau src/shared/AudioConfig.luau` — прочитать целиком.
2. Проверить, что клиент совпадает с тем, как сервер реально выставляет атрибуты:
   - `NewRecord` выставляется в `CompleteRun` и сбрасывается в `resetRunDisplay` — HUD перечитывает его на `player.AttributeChanged`;
   - `Flawless_<RuleId>` — целое ≥ 0 (0 = нет); `PlayerHints.flawlessCount` игнорирует 0 и мусор;
   - `RunSurvived` при Forfeited не растёт (тогда защита в `RunFeedback` безвредна; оставить);
   - порядок `LastTrialOutcome` / `RunSurvived` не даёт двойного тоста.
3. Если поведение сервера отличается от описанного в п.0 — поправить клиент, не сервер, и добавить проверку в `tests/PlayerHints.spec.luau`, если затронуты тексты.

## 3. Документация пакета

По образцу `docs/FIRST_SESSION.md`. Основной отчёт — `docs/SECOND_PACKAGE.md` (черновик есть; дописать, не создавать второй).

Отчёт должен покрыть **все изменения сессии**: HUD TextBounds (дочерний ограничитель, запрет `.TextBounds.` в check_sources); SafeZone (серый пол без старого символа); поздний вход (`lateEntryNotice`, Forfeited как участие); сохранения (shutdown ждёт всю работу хранения, освобождение только своего `Session.Owner` после неуверенного захвата/утраты аренды, финальное сохранение только при живой аренде); категории колоды (Spatial/Reflex/Movement, не более двух подряд); LavaRise (подъём перекрывающихся игроков); DisappearingTiles (случайная диагональ); RedLight (плитка под игроком исчезает после зелёного); LowGravity (две волны «ПРОВАЛ ⚠» + 6 плиток); LaserSweep 40; мягкая проверка движения (1-е нарушение — предупреждение без награды, повтор — выбывание); RunEnergy (личный вклад в итоге); рекорды (schema v2, NewRecord, Flawless, практика); Forfeited; звук WarningFinal/Safe/Forfeited; «Позвать друзей».

Шаги:
1. `docs/SECOND_PACKAGE.md`: заменить таблицу чисел финальными результатами п.5; переписать «Проверку чужого diff» на «Проверку итогового diff» (п.4); убрать абзац «Build.ps1 целиком не запускался», если в среде Codex `Build.ps1` пройдёт полностью (у Codex `%LOCALAPPDATA%\RobloxDev\bin` содержит luau, luau-compile, lune, rojo, stylua, selene).
2. `Roadmap.md` → раздел «Второй пакет»: добавить строку про Forfeited (GP01/UX01) и FinaleSuccess (GP07); статусы — «реализовано, проверено локально», native — «ожидает проверки».
3. `Dashboard.md` → «Текущая итерация»: упомянуть Forfeited и итоговый статус прогона.
4. `Evidence Index.md`: строка SECOND_PACKAGE с финальными числами; оставить пометку, что до коммита у пакета нет SHA/манифеста.
5. Если пакет будет зафиксирован позже — создать `docs/qa/second-package.json` по образцу `docs/qa/first-session.json` (SHA, hash `build/RuleRoom.rbxlx`, версии инструментов, числа). **До коммита не создавать SHA-ссылок.**
6. `python tools/obsidian/verify_vault.py` → `passed: true`.

Формулировка честности обязательна везде: «проверено локально (lune, адаптеры), не в Studio, не на устройстве, не в облаке, звук не прослушан, приглашения не проверены».

## 4. Проверка итогового diff

1. `git diff --stat` и полный `git diff` по `src/server`, `src/shared`, `tests`, `tools`, `docs/ALPHA_CONTRACT.md`.
2. Чек-лист: нет двойных наград (Forfeited, смерть, поздний вход); Flawless только для награждённого выжившего без урона; рекорды один раз за забег; миграция v0/v1→v2 не теряет баланс; клиент не решает исходов и наград; русский текст + символ + цвет у каждого исхода; ассеты только через `build_assets.py`.
3. Найденные расхождения — исправить, отметить в отчёте.

## 5. Итоговая проверка всего вместе

Из корня проекта:

```powershell
. tools/environment/Enter-DevEnvironment.ps1   # если работает в среде Codex
powershell -ExecutionPolicy Bypass -File .\Build.ps1
```

`Build.ps1` выполняет: `build_assets.py` → `verify_world.py` → `check_sources.py` (StyLua --check, Selene, luau-compile всех файлов, запрет `.TextBounds.`) → `rojo build` + sourcemap → `verify_place.py` → spec через `luau` → integration через `lune` → `verify_model.luau`.

Дополнительно (требование пакета — все тесты через lune):

```powershell
Get-ChildItem tests -Filter *.luau | ForEach-Object { lune run $_.FullName; if ($LASTEXITCODE) { throw $_.Name } }
python tools/obsidian/verify_vault.py
git status --short assets   # после build_assets.py ассеты не должны меняться повторно
```

Приёмка: всё зелёное; числа каждого набора записаны в `SECOND_PACKAGE.md`. Последний известный зелёный прогон (до завершения phase0): PlayerHints 136, ArenaRules 4222/9, PlayerRoster 91/19, ProfileData 123, ProfileService 110/17, StationAdmission 66, RuleDeck 27031, RuleMath 2086, RunPresentation 218, ProfileStatus 30, PracticePolicy 17; Rojo 1029 экземпляров; check_sources — 35 файлов.

## 6. Нативная проверка (только если Studio MCP вернёт редактор)

Не обязательна для закрытия пакета; без неё в отчёте честно «не проверено в Studio».

1. Перечислить студии MCP, выбрать одну; один владелец ввода. Не требовать PlayerModule через MCP.
2. Сценарии: Rule → MovementWarning → Forfeited → Results на 750×381, 666×374 и ПК (строка не перекрывает таймер, джойстик, прыжок; «!» в полоске); Results с `NewRecord = "Score,Survived"` + предупреждением сохранения; шкафчик → Задания с атрибутами и без, прокрутка; RedLight/LowGravity/DisappearingTiles/LavaRise двумя клиентами; Warning → WarningFinal → Danger → Safe с mute и reduced motion.
3. Снимки/JSON в `docs/qa/` и `docs/media/`, ссылки — в Evidence Index. Не называть статическую сборку плейтестом.

## 7. Итоговый ответ пользователю

- что сделано по пунктам 1–5 (и 6, если было);
- числа прогона;
- найденные и исправленные расхождения;
- что не проверено (Studio, телефон, облако, звук, приглашения);
- напоминание: ничего не закоммичено и не опубликовано.
