---
project: boblox
updated: 2026-10-24
---

# Забег, допуск и результат

Фазы: Waiting → Voting → Rule → Break, после шестого испытания Results → новое Voting. Main владеет переходами, PlayerRoster — составом допущенных участников. Поздний вход и возрождение не включают игрока посреди опасности; допуск происходит на следующей границе.

Три независимых понятия: персонаж жив; участник допущен и имеет право на survival-награду; команда набрала нужный заряд. Положительное HP или достаточный charge сами по себе не означают победу.

Победа по контракту требует минимум четырёх успешных испытаний, выживания в финале и успеха реактора. Награда завершения выдаётся участнику с хотя бы одним успешным испытанием; победный бонус — отдельно. В кандидатном исправлении итог финала учитывает реально принятых финальных выживших, включая нижний порог награды. Сверять версию Main/PlayerRoster: baseline и QA-кандидат могут отличаться.

Cleanup возвращает gravity, плитки и луч; динамические эффекты удаляются. Проверка `productionRestored` снимается **до** аварийной очистки fixture, иначе fallback мог бы скрыть дефект.

Смерть/reset/leave — разные события. Проверенная естественная гибель после заряда не закрывает disconnect последнего игрока в каждый момент финала; эти границы остаются в [[07-Tasks/Roadmap]].

Источники: [ALPHA_CONTRACT](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/ALPHA_CONTRACT.md), [Main](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/server/Main.server.luau), [PlayerRoster](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/server/PlayerRoster.luau). [[03-Gameplay-Systems/Progression and Saves]] · [[06-Testing/Verification]] · [[00-Dashboard/Dashboard]]
