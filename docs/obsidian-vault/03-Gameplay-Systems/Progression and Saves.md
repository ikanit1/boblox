---
project: boblox
updated: 2026-10-24
---

# Прогресс, экономика и сохранения

| Событие | Coins | XP |
|---|---:|---:|
| Пройденное испытание | 12 | 20 |
| Принятая звезда/заряд | 2 | 3 |
| Завершённый забег с хотя бы одним успехом | 15 | 25 |
| Победный бонус | 20 | 0 |

Точные значения авторитетны в [EconomyConfig](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/src/shared/EconomyConfig.luau), таблица — читаемое описание текущей версии. Следы None/Cyan/Pink/Gold/Emerald стоят 0/60/100/180/260 монет. Задания survive/stars/runs: цели 8/10/2, награды 50/50/60 монет. Смена дня UTC не отнимает накопления; награда задания однократна.

ProfileData schema v1 хранит Coins, XP, Wins, owned/equipped trail, день и задания. Здоровье, персонаж и текущий забег не сохраняются. Session Score/Best — не облачный рейтинг. Уровень не меняет физику.

Облачный путь: UpdateAsync, lease 180 s, автосохранение около 45–53 s, последовательные записи, WriteToken, ограниченные повторы и shutdown 25 s. Ошибка загрузки или Busy разрешают явно обозначенный session-only fallback, который не перезаписывает облачный профиль.

В обычном Studio `StudioDataStoreEnabled=false` и `TestPlaceId=0`: после остановки Play данные исчезают. Основной store RuleRoomProfiles_v1 и отдельный TEST_v1 различаются. Локальные 59 pure + 27 integration проверок в 9 сценариях не доказывают реальный облачный вход/выход. Последний требует отдельно разрешённой приватной test experience и совпадающего положительного TestPlaceId.

Подробности и сценарии: [SAVES](https://github.com/ikanit1/boblox/blob/afdbc080023d3c4ff785805aff44b214ee1b6ca7/docs/SAVES.md). Robux-продуктов, платежей или торговли в этой альфе нет.

[[03-Gameplay-Systems/Round Lifecycle]] · [[10-Releases/Release Checklist]] · [[00-Dashboard/Dashboard]]
