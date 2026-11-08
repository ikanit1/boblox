---
project: boblox
updated: 2026-11-08
---

# Индекс доказательств

## Текущая интегрированная версия

Общая проверка завершена: Build, 41 набор Lune, 37 Python-тестов; fingerprint `39662c99…502c1e2e`. Точная идентичность приведена в PRODUCT_COMPLETION, native-приёмка не подразумевается.

[PRODUCT_COMPLETION](../../PRODUCT_COMPLETION.md) и [qa/product-completion.json](../../qa/product-completion.json) содержат текущий полный прогон и fingerprint. Предыдущие EXPERIENCE_PACKAGE/ROADMAP_PROGRESS сохраняют собственные результаты и не суммируются с новым отчётом. Независимый review охватил новые опасности/финал, повтор загрузки, клиентские схемы и упаковку. Native/device/cloud/capacity/human не заявлены.


Последний пакет: [EXPERIENCE_PACKAGE](../../EXPERIENCE_PACKAGE.md), звук/наблюдение/изолированные опыты. Его локальные проверки и два артефакта фиксируются отдельно от предыдущего ROADMAP_PROGRESS. Ни Studio, ни устройства/облако/прослушивание/реальные 12 клиентов не проверены. Fingerprint входов относится к фактическому незакоммиченному дереву, не к базовому SHA.


Предыдущий пакет roadmap — незакоммиченное дерево поверх `08ba71e`. [ROADMAP_PROGRESS](../../ROADMAP_PROGRESS.md) содержит результаты общей проверки и открытые gates; `build/candidate-manifest.json` связывает реальную сборку с входными файлами, включая untracked, а не выдаёт HEAD за её SHA. Проверка актуальности — `python tools/candidate_manifest.py verify`. Studio, физические устройства, облако, 12 native-клиентов и человеческий плейтест **не выполнены**. Инструкция диагностической записи — [LOCAL_QA](../../LOCAL_QA.md).


Предыдущий пакет: второй пакет 2026-11-08 — незакоммиченное рабочее дерево поверх `08ba71e`; [SECOND_PACKAGE](../../SECOND_PACKAGE.md) фиксирует полную Build.ps1 (компиляция 39 файлов, StyLua, Selene 0/0/0, Rojo 1029 экземпляров, verify_world/place/model), все 15 `tests/*.luau` отдельно через Lune и повторяемую генерацию assets. Native, облако, физическое устройство, звучание и реальные приглашения не проверены; MCP вернул `studios: []`. До коммита у пакета нет собственного SHA и манифеста; локальную собранную версию нельзя выдавать за проверенный релизный RC.

Предыдущий пакет: `8f45a0aa9f99ef1b654ca9a94cddb3cce0511851`, 2026-11-08. [FIRST_SESSION](../../FIRST_SESSION.md) и [first-session.json](../../qa/first-session.json) фиксируют проверенную локальную сборку, source blobs, hash артефакта и открытые native/device/cloud ограничения. 12 имитированных участников в сценарии метеоров не означают 12 Roblox-клиентов. Старые свидетельства ниже не пересчитываются на эту версию.

| Свидетельство | Содержимое / граница |
|---|---|
| [QA_REPORT](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/QA_REPORT.md), [PLAYTEST](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/PLAYTEST.md) | Историческая альфа 0.3; не подменяет последующую матрицу |
| [RULE_ACCEPTANCE — ветка проверки](https://github.com/ikanit1/boblox/blob/test/full-rule-acceptance/docs/RULE_ACCEPTANCE.md) | 32 zero-delay + 10 clean-delay runtime cases, solo, pickup; смешанные уровни явно разделены |
| [MULTIPLAYER_QA — ветка проверки](https://github.com/ikanit1/boblox/blob/fix/multiplayer-lifecycle/docs/MULTIPLAYER_QA.md) | Два Main-забега, lifecycle 27/147, Vote 8, native leave/empty-return и ограничения нагрузки |
| [SAVES](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/SAVES.md) | 59 pure + 27 integration / 9 локальных сценариев; облачный путь не принят |
| [SECOND_PACKAGE](../../SECOND_PACKAGE.md) | 15 наборов / 34475 проверок: ArenaRules 4345/10; Roster 159/32; ProfileData 123; ProfileService 110/17; StationAdmission 66; PlayerHints 209; RuleDeck 27031; RuleMath 2086; RunPresentation 229; FinaleSuccess 9; RunFeedback 30/10; AudioController 17/3; StationInvites 14/3; PracticePolicy 17; ProfileStatus 30. Локальные адаптеры, не native/cloud/device/звучание/приглашения |
| [AUDIO](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/AUDIO.md) | Происхождение двух звуков, engine-signal/mute/lifecycle; не слуховой тест |

Raw evidence намеренно исключено из Git и передаётся отдельным `RuleRoom-QA-evidence-2026-10-23.zip`. В локальном рабочем каталоге прошлой итерации данные находятся в соседних RuleRoomAcceptance/evidence и RuleRoomMultiplayer/evidence. Эти machine-specific пути не являются публичными CI-артефактами; не создавать фальшивые raw-ссылки в GitHub.

Текущая среда создана от PR1 `afdbc080023d3c4ff785805aff44b214ee1b6ca7`. Исторический baseline в Roadmap — `2d2c3b924f184c3ebb1c2621fe0fcc9ffc8df5f3`; кандидат матрицы объединял PR2/PR3 и адресные изменения HUD/текста. Проверять Source manifest конкретного экспорта, а не считать документы доказательством автоматического merge.

Контрольные числа последней матрицы: clean-delay 10/10 строк PASS, 223 checks PASS, 20 условий N/A (zero-delay budget), 0 FAIL/UNVERIFIED. Solo: 12 trial/2 run ledger. Main два клиента: 24 trial-player/4 run-player ledger. Lifecycle: 27 commands/147 assertions. Ни одно число не означает 12-client gameplay.

Фиксировать новый результат рядом с его кодом и датой; старый raw не перезаписывать. Когда PR будет слит, обновить указатели состояния, сохранив исторический SHA.

[[06-Testing/Verification]] · [[10-Releases/Release Status]] · [[00-Dashboard/Dashboard]]
