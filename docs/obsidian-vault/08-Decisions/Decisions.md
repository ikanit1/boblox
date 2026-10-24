---
project: boblox
updated: 2026-10-24
---

# Принятые решения

| Решение | Причина | Где закреплено |
|---|---|---|
| Один репозиторий boblox, файловые Rojo-исходники авторитетны | Проверяемый diff, воспроизводимая сборка, отсутствие второго проекта | [AGENTS](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/AGENTS.md), [[02-Architecture/Architecture]] |
| Сервер решает исходы и деньги | Клиент передаёт только намерение | [ALPHA_CONTRACT](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/ALPHA_CONTRACT.md) |
| Шесть испытаний, общий финал, возврат в следующее испытание | Короткий цикл с личным и командным результатом | [[01-Game-Design/GDD]] |
| Косметика за заработанные монеты без физического преимущества | Справедливый ранний тест ядра | [[03-Gameplay-Systems/Progression and Saves]] |
| Studio Session по умолчанию, отдельный test store | Не повредить реальные данные при разработке | [SAVES](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/SAVES.md) |
| Только один оператор Studio, файлы разделены между агентами | Избежать противоречивых live-правок | [[02-Architecture/Source Map]] |
| QA фиксирует уровень и ограничения, Complete не равен PASS | Сохранить достоверность результатов | [[06-Testing/Verification]] |
| Roadmap/checklist каноничны в vault, прежние docs — указатели | Одна актуальная версия плана при удобной навигации | [[07-Tasks/Roadmap]], [[10-Releases/Release Checklist]] |

Это реестр существующих решений, а не ретроспективное одобрение новых фич. Для изменения контракта сначала описать проблему, варианты, последствия и требуемую регрессию; записать решение в reviewable diff.

[[00-Dashboard/Dashboard]]
