---
project: boblox
updated: 2026-10-24
---

# Индекс доказательств

| Свидетельство | Содержимое / граница |
|---|---|
| [QA_REPORT](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/QA_REPORT.md), [PLAYTEST](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/PLAYTEST.md) | Историческая альфа 0.3; не подменяет последующую матрицу |
| [RULE_ACCEPTANCE — ветка проверки](https://github.com/ikanit1/boblox/blob/test/full-rule-acceptance/docs/RULE_ACCEPTANCE.md) | 32 zero-delay + 10 clean-delay runtime cases, solo, pickup; смешанные уровни явно разделены |
| [MULTIPLAYER_QA — ветка проверки](https://github.com/ikanit1/boblox/blob/fix/multiplayer-lifecycle/docs/MULTIPLAYER_QA.md) | Два Main-забега, lifecycle 27/147, Vote 8, native leave/empty-return и ограничения нагрузки |
| [SAVES](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/SAVES.md) | 59 pure + 27 integration / 9 локальных сценариев; облачный путь не принят |
| [AUDIO](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/AUDIO.md) | Происхождение двух звуков, engine-signal/mute/lifecycle; не слуховой тест |

Raw evidence намеренно исключено из Git и передаётся отдельным `RuleRoom-QA-evidence-2026-10-23.zip`. В локальном рабочем каталоге прошлой итерации данные находятся в соседних RuleRoomAcceptance/evidence и RuleRoomMultiplayer/evidence. Эти machine-specific пути не являются публичными CI-артефактами; не создавать фальшивые raw-ссылки в GitHub.

Текущая среда создана от PR1 `afdbc080023d3c4ff785805aff44b214ee1b6ca7`. Исторический baseline в Roadmap — `2d2c3b924f184c3ebb1c2621fe0fcc9ffc8df5f3`; кандидат матрицы объединял PR2/PR3 и адресные изменения HUD/текста. Проверять Source manifest конкретного экспорта, а не считать документы доказательством автоматического merge.

Контрольные числа последней матрицы: clean-delay 10/10 строк PASS, 223 checks PASS, 20 условий N/A (zero-delay budget), 0 FAIL/UNVERIFIED. Solo: 12 trial/2 run ledger. Main два клиента: 24 trial-player/4 run-player ledger. Lifecycle: 27 commands/147 assertions. Ни одно число не означает 12-client gameplay.

Фиксировать новый результат рядом с его кодом и датой; старый raw не перезаписывать. Когда PR будет слит, обновить указатели состояния, сохранив исторический SHA.

[[06-Testing/Verification]] · [[10-Releases/Release Status]] · [[00-Dashboard/Dashboard]]
