# Stage 2 — multiplayer и жизненный цикл

Дата начала: 23 октября 2026. **Статус: два production Main-забега на двух клиентах PASS; lifecycle 27 команд/147 assertions PASS; Vote 8 сценариев одного клиента PASS; native leave-vote/empty-return production-путь подтверждён. Полная Stage 2 не закрыта.** Четыре и восемь клиентов не запускались из-за ресурсов среды; двенадцать отклонены API Studio. Длительный production perf-экспорт не получен. Ветка `fix/multiplayer-lifecycle` основана на PR3; runtime `RuleRoomVerification` использует PR2. Свидетельство этой композиции не означает merge. Публикация Roblox запрещена текущей задачей; облачные DataStore здесь не проверяются.

## Реальные клиентские сессии и предел среды

Под клиентом здесь понимается отдельная запущенная клиентская сессия Roblox Studio с собственным LocalPlayer, репликацией, GUI, кадрами и подтверждённым участием в тесте. Автоматический ввод в такую сессию не превращает её в NPC. Dummy-модели, дополнительные серверные Humanoid и подмена Players не считаются клиентами.

Официальные [Studio testing modes](https://create.roblox.com/docs/studio/testing-modes) и [StudioTestService](https://create.roblox.com/docs/reference/engine/classes/StudioTestService) указывают максимум **8 клиентских сессий**. На установленной Studio **0.744** запрос `ExecuteMultiplayerTestAsync(12)` фактически отклонён: `Accepted=false`, `Complete=true`, ответ `number of players should be integer between 0 and 8`. Источник: `evidence/capacity-probe-result.json`. Это **LIMIT для локальной приёмки 12**, а не PASS нагрузки; публикация или обход ограничения ради этого не выполняются.

| Число | Прежнее доказательство | Новая проверка / критерий | Статус и evidence |
|---|---|---|---|
| 1 | Правила изолированно; исторические solo-проверки | Текущий полный production-цикл; базовый trace времени/ресурсов | Main 6/6 + exact4/6 PASS, 12 trial/2 run ledger; RuleRoomAcceptance/evidence/solo. Это не многоклиентная нагрузка |
| 2 | Candidate: два полных production-забега, 24 trial-player/4 run-player проверки, без MovementViolation | Текущий lifecycle, сеть и согласованность всех клиентов | Новые Main success/charged_die PASS:24 trial/4run ledger; lifecycle 27/147; Vote 8; native leave-vote и empty-return подтверждены. Остальные ограничения ниже |
| 4 | Нет подтверждённого прогона | Четыре LocalPlayer/handshake; полный цикл + повтор, единые Round/RuleIndex/Phase, награды каждому | NOT RUN: ожидается освобождение ресурсов среды; нет экстраполяции с двух |
| 8 | Нет подтверждённого прогона | Восемь реальных клиентов; полный цикл + повтор, lifecycle/ресурсы/cleanup | NOT RUN: ожидается освобождение ресурсов среды; не проверялось |
| 12 | Официальный предел и фактический отказ API установленной Studio | Запрос 12 отклонён до запуска; 12 клиентских сессий не были проверены. Gate остаётся открытым при запрете публикации | LIMIT: evidence/capacity-probe-result.json, Accepted=false |

Новые протоколы сохраняются в `RuleRoomMultiplayer/evidence`. Манифест содержит исходники/fixture SHA, клиентские session ID и UserId, версии Studio, сеть, режим управления, длительность, данные каждого клиента. Одного server Players count недостаточно без клиентских подтверждений.

## Production Main: два клиента, успешный и неуспешный финал

[production/server-export.json](../evidence/production/server-export.json): 31 запись, `Complete=true`, `Status=PASS`, `SummaryPassed=true`. Два настоящих клиента-1/-2 играли production Main/ProfileService с Session-данными и обычным MoveTo/Jump driver. Сценарии `success` и `charged_die` достигнуты. Наблюдатель длился 492.23s, включая ожидание первого старта; это не чистая длительность двух забегов.

| Забег / игрок | Исход | Начислено Coins / XP / Wins | Итоговый баланс Coins / XP / Wins |
|---|---|---|---|
| Round1 / Player1 |6/6,15 pickup, жив, общий charge11/5, finale=true |+137 /+190 /+1 |137 /190 /1 |
| Round1 / Player2 |6/6,5 pickup, жив, общий charge11/5, finale=true |+117 /+160 /+1 |117 /160 /1 |
| Round2 / Player1 |5/6,15 pickup, HP0 после достижения charge5/5; finale=false |+105 /+170 /0 |242 /360 /1 |
| Round2 / Player2 |5/6,5 pickup, HP0 после достижения charge5/5; finale=false |+85 /+140 /0 |202 /300 /1 |

Во втором финале оба персонажа действительно погибли при обычном движении к лучу: `allEliminated=true`, `caseAchieved=true`, zero injections в Summary, нет `FaultInjection` записей. Это **не Health0-инъекция**. Заряд 5/5 не выдал ложную победу: Wins остались 1 у каждого, финальная survival-награда 0. Отдельные финальные дельты —19 Coins/31 XP и 21 Coins/34 XP: pickup и обычный completion, без survival/win. Текст «Заряд есть, но все выбыли» наблюдался в реальном Results.

**24/24 trial-player и 4/4 run-player ledger PASS**. Аудит независимо пересчитал формулы `Coins=12×survival+2×pickups+15×completion+20×win`, `XP=20×survival+3×pickups+25×completion`; сумма trial-дельт совпала с каждым run ledger. ResultsStable обоих забегов показывает `noExtraAwards=true`, MovementViolation в записанных снимках пуст. Все Break/Results/Voting-восстановления истинны; после первого Results есть следующий Voting.

## Vote: восемь сценариев реального клиента

[production/vote-1.json](../evidence/production/vote-1.json) содержит 8/8 `passed=true`, роль tester, Complete/Passed=true; восемь настоящих FireServer-попыток. Проверены: отвергнутый второй голос через 0.130s, разрешённая последующая смена, payload false/table/unknown/nil, запрос вне Voting и сброс в следующем Voting. После ограничения частоты остался серверный Reflex с правильной галочкой; после принятой смены появился Cosmic. Невалидные запросы не поменяли подтверждённый выбор; следующий Voting сбросил VotedMode, галочки и счётчики.

Это наблюдение реального реплицированного VotedMode и текстов карточек. Оно не является нажатием UI-кнопок, pixel-proof или доказательством всех конкурентных выборов нескольких клиентов. [production/vote-2.json](../evidence/production/vote-2.json) имеет роль read_only_observer и RequestsSent0: его один снимок не считается второй серией восьми тестов. Уход проголосовавшего проверен следующим отдельным протоколом.

## Native leave-vote, пустой Main и новый клиент

[production/leave-export.json](../evidence/production/leave-export.json) содержит 5 записей, Complete=true, EmptyReached=true, ReturnPassed=true. Клиент-1 имел принятый Reflex и нативно вышел во время Voting: `voteCleared=true`, VotesReflex=0. Последний оставшийся клиент-2 нативно вышел во время Rule. Тот же production Main достиг Waiting с count0, AliveCount0, RuleEffects0, gravity196.199997 и FinaleSuccess=false; это уже не ручной CheckEmpty прежнего lifecycle-стенда.

Затем в тот же сервер вошёл новый native клиент-3. Финальный снимок: Round6/RuleIndex2, MeteorRain, DataStatus=Session, InRound=true, HP100, MovementViolation пуст, начальные Coins/XP/Wins0. Сервер возобновил игровой цикл. Это **новый UserId с новым локальным профилем**, а не облачное восстановление прежнего игрока. Одновременно было максимум два клиента; последовательная смена на-3 не является тестом трёх клиентов. Сам leave-экспорт не содержит отдельного финансового ledger ушедших; утверждение об успешных выплатах относится к двум забегам выше.

Длительный production perf-экспорт **не состоялся**: `performance-first.json`, `performance-last.json`, `performance-server.json` имеют Complete=false и пустые entries. QA-сериализация превысила StringValue-лимит 200000 (сообщение 306845);600s raw summary недоступен. Исправленный SchemaVersion2 collector прошёл короткий Studio smoke примерно 23s: server/client Complete=true, по 23 Snapshot+Summary; файлы `RuleRoomAcceptance/evidence/pickups/perf-v2-server.json` и `perf-v2-client.json`. Main/опасности в smoke выключены: это проверка исправленного экспорта, **не замена production600s benchmark**. Старые короткие lifecycle-замеры ниже тоже не заменяют его. В `production/console-after.json` есть QA pickup preflight-ошибки и ошибка perf-collector; чистая консоль этой сессии не заявляется. Ошибки измерительного кода сохранены отдельно от игровых ledger-сценариев.

Production-прогон подтверждает два конкретных исхода, выплаты двум игрокам и описанный native leave/return. Он не заменяет уход до/после зарядки финала, облачную запись,4/8/12 клиентов или длительный perf-повтор под активными опасностями.

## Lifecycle-матрица

| Case ID | Действие | Критерий приёмки | Прежнее доказательство | Новый результат |
|---|---|---|---|---|
| JOIN-RULE | Новый клиент подключается в активную опасность | Лобби/наблюдение; InRound=false, нет награды за пропущенное испытание; следующий допустимый старт — HP 100 и правильная камера | Admission исторически 0.2, текущего повторного доказательства нет | Частично: native replacement-3 пришёл в fixture Rule, InRound=false/награды 0, следующий BeginTrial допущен. Реальной опасности и Main в стенде нет |
| JOIN-PHASE | Вход в Waiting/Voting/Break/Results | Готовый профиль допускается только на разрешённой границе; нет неверного RuleIndex, зависания или двойного старта | Реализация имеется | Возврат нового native клиента после Waiting подтверждён в Main; отдельные входы во все другие фазы не покрыты |
| LEAVE-VOTE | Проголосовавший выходит до закрытия Voting | Его голос удалён, итоговые счётчики и выбранный режим согласованы | Старые базовые проверки не покрывали текущий случай | PASS native-1 leaveVoting с Reflex: voteCleared=true/VotesReflex0. Не полный перебор конфликтующих голосов |
| LEAVE-LAST-ALIVE | Последний живой участник выходит во время Rule | Испытание заканчивается/переходит по контракту без ложной награды и остаточной опасности | Общая гибель проверена; выход — отдельный путь | Последний native-2 вышел во время Rule; Main Waiting/count0/effects0, finale=false. Отдельный ledger ухода не записан |
| EMPTY-RETURN | Все клиенты уходят, затем появляется новый | Сервер не зависает, приходит в Waiting; новый игрок запускает корректный следующий цикл | Прежний CheckEmpty был ручным | PASS production-переход: EmptyWaiting, затем новый native-3 в Round6 Rule, Session/InRound/HP100. Не облачный rejoin |
| RESET-RESPAWN | Reset/смерть во время опасности; несколько быстрых повторов | Нет повторного допуска в тот же hazard, survival не повторяется; следующий trial HP 100; корректные camera/controls/collision groups | Коллизии: 22 локальных lifecycle assertions; общий gameplay reset требует повторения | По одной Health 0-инъекции каждому из двух клиентов: respawnHP100, новое character ID, InRound=false, награды 0, группы назначены. Не пользовательское Reset menu; опасности выключены |
| FINAL-LEAVE | Уход участника до и после достаточного заряда; отдельно последний живой | Goal/charge соответствуют зафиксированной политике состава; покинувший не получает новую награду; нет успеха без допущенного финального выжившего | Смерть после заряда проверена; disconnect не эквивалентен смерти | Ожидает |
| PROFILE-LATE | Профиль ещё Loading при старте и становится готов позже | Нет допуска/награды до IsReady; готовность посреди Rule не добавляет в опасность; следующий trial работает | Локальные ProfileService tests есть, admission Main вместе с задержкой ещё не подтверждён | PASS для proxy.IsReady=false у -1: исключён, состояние неизменно, следующий BeginTrial допущен. Это artificial admission gate, не настоящая загрузка DataStore |
| REMOTE-INVALID | Неизвестные mode/action/id, неверный тип, запрос вне фазы/без права | Валюта, право владения и исходы не меняются; сервер не падает | Историческая 0.2 серия 30 запросов | ProfileAction96 malformed attempts без изменения; Vote false/table/unknown/nil и внеVoting отклонены, HUD согласован. Не каждый отдельный validator подтверждён |
| REMOTE-BURST | Серия быстрых корректных/некорректных Vote/ProfileAction | Rate limit соблюдён, принятый выбор совпадает с сервером, покупка/claim без дубля | Бывший U1 optimistic vote проверяется реальной репликацией | ProfileAction12×0.4s+36×0.02s на клиента без изменения; Vote второй через 0.130s отклонён, последующая смена принята. Точные bucket drops и valid purchase/claim не измерены |
| COLLISION-GROUPS | Два/восемь игроков пересекаются; новые части, respawn | Нет взаимного выталкивания/ложного Airborne; мир collidable; политика сохраняется и очищается | Collisions candidate4cases + lifecycle 22 и combined2clients PASS | Назначение групп после двух respawn и replacement admission подтверждено; восемь клиентов не запускались |
| CLIENT-LIFETIME | Несколько забегов, смерть/выход цели наблюдения, повторный HUD | Правильная CameraSubject; по одному HUD/аудиопулу, четыре голоса; нет старых подписок; локальный mute независим | Подробные 0.3 аудио/UI и collision lifecycle; не полная текущая серия | Ожидает |

Перед FINAL-LEAVE записать ожидаемую политику цели из текущего кода, чтобы не подбирать её под результат. Не смешивать доступность с сохранением данных: Session-файлы не должны внезапно обращаться к облаку.

## Двухклиентный lifecycle: выполненные команды и границы

[lifecycle/server-outcomes.json](../evidence/lifecycle/server-outcomes.json) содержит **27/27 `ok=true`,147/147 именованных `passed=true`**. Стенд использует production PlayerRoster и ProfileService с Session-данными, собственные ручные границы BeginTrial/FinishTrial. **Main выключен, ArenaRules не запускаются:** в фазе с названием Rule нет работающей опасности. Это позволяет отдельно проверить допуск, смерть, состав roster и защиту профиля, но не заменяет полный игровой цикл.

Начальные реальные LocalPlayer — UserId-1/-2. После native ухода-2 подключён новый native клиент-3. Это **три уникальные сессии последовательно, максимум две одновременно**, не трёхклиентный нагрузочный тест. Клиентские handshake, acknowledgements и отдельные performance-отчёты присутствуют.

| Команды | Что фактически подтверждено |
|---|---|
| 1–10 | Допуск двух игроков; Health 0-инъекции поочерёдно-1 и-2; новые character ID 1→3 и 2→4, lobbyHP100, отсутствие повторного допуска в текущий trial и лишней награды; следующий trial допускает обоих |
| 11–15 | Только proxy.IsReady для -1 возвращаетfalse на очередной допуск; enters1, исключённый не получает награду, после разблокировки enters2 на следующей границе |
| 16–17 | Каждый клиент отправил 12 malformed ProfileAction с task.wait 0.4s и 36 с 0.02s: всего 96 попыток; ack от обоих, transportErrors 0, авторитетный профиль до/после совпал |
| 19–24 | Native уход-2, затем replacement-3 во время активного fixture trial; он остаётся InRound=false и без награды за пропущенный trial; следующий BeginTrial допускает -1/-3 |
| 25–27 | Оба оставшихся клиента нативно ушли; playerCount 0/aliveCount 0, roster пуст. CheckEmpty вручную завершил fixture trial; Stop восстановил respawn/state, Main остаётся намеренно выключенным до возврата оператором |

Во всех 8 FinishTrial возврат повторного AwardSurvivors равен 0; исходные вызовы выдали суммарно 12 положенных survival-наград. Проверены индивидуальные начисления и сброс допуска. Это не run-win/CompleteRun и не возврат Main в Waiting.

Token bucket ProfileAction имеет capacity 5/refill 2 per second и расходуется до payload validation. Поэтому 96 подтверждённых попыток и неизменный server state не доказывают прохождение всех 96 через каждый validator. Пауза 0.4s — заданное ожидание клиента, а не гарантия такого же промежутка доставки; burst0.02s может отсеиваться раньше. Не отправлялись корректная покупка, claim или Vote; эти ветки не помечены PASS.

Завершение стенда и пустой roster сохранены; `lifecycle/end.json` подтверждает остановку теста. Последующее финальное восстановление среды подтверждено в разделе завершения ниже.

## Сеть, время и ресурсы

Минимальная последовательность: 1/2/4/8 клиентов без добавленной задержки; затем адресные warning/движение/lifecycle при настроенной задержке/потерях на 2 и максимальном доступном числе. Точные значения профилей и допуски утверждаются в manifest до запуска. Исходные пользовательские настройки — 500 ms в каждую сторону, 0.5% потерь в каждую сторону, jitter0; прежний возврат этих настроек не является их игровым тестом.

| Профиль сети | Клиенты | Настроено / реально наблюдалось | Сценарии | Статус |
|---|---|---|---|---|
| Без добавленной задержки |1/2/4/8 | Delay/loss/jitter и фактический ping записать | Цикл, согласованность, награды, основные lifecycle | Solo и Main 2 production, ограниченный lifecycle 2 выполнены;4/8 не запускались; остальные переходы отдельно |
| Контролируемая задержка/потери | 2 и максимум доступных |100/100ms, jitter20ms, loss0.5% в clean-delay Stage 1 | Все 10 правил, client warning→hazard, реальные прыжки | Два клиента: индивидуальные правила/timers PASS; late join/leave при задержках и максимальный count не проверены |
| Исходные настройки пользователя | Максимум доступных по результату ресурсоёмкости | 500/500 ms, 0.5/0.5%, jitter0 | Контроль деградации и корректности исходов; не обещание «незаметной» задержки | Ожидает |

На каждом размере записывать p50/p95 client frame dt и server step dt, память/CPU процесса, сетевой ping, число объектов/RuleEffects/подписок или их наблюдаемые аналоги в одинаковых точках начала/конца. Это локальный benchmark машины, не физического телефона. Числовые пороги производительности не выдаются за стандарт Roblox; если лимит среды не позволяет полноценный прогон, статус LIMIT с фактическими числами.

### Наблюдения производительности lifecycle-стенда

| Сессия / файл в evidence/lifecycle | Наблюдалось s / кадров | p50 / p95 deltaTime ms | Максимум ms | Peak Roblox Stats memory MB |
|---|---|---|---|---|
| Client-2, perf-client2.json |113.713 /6668 |16.654 /17.876 |182.913 |1689.3 |
| Client-1, perf-remaining-0.json |220.575 /13061 |16.661 /17.979 |158.817 |1698.4 |
| Replacement-3, perf-remaining-1.json |95.301 /5595 |16.639 /17.864 |116.165 |1739.8 |
| Server, perf-server.json |234.751 /14059 |16.941 /18.030 |155.193 |1531.6 |

Источник клиентского cadence — RenderStepped, серверного — Heartbeat. Это **интервал вызовов, не CPU/GPU execution time**. Percentile nearest-rank рассчитаны по записанным значениям; ring capacity 20000 не обернулся, `discardedOlderSamples=0`. В этих четырёх отчётах нет observer errors или dropped metadata; данные собирались примерно раз в секунду. Память получена через `Stats:GetTotalMemoryUsageMb`, а не отдельный OS working-set замер процесса. Снимки содержат QA-объекты и переходы между 1/2/0 клиентами; влияние самого наблюдателя сохраняется в `observerCaptureCostMs`.

Main и опасности в этом стенде выключены. Поэтому p95≈18ms не является benchmark полноценного геймплея на 8 клиентах, стабильным 60FPS, доказательством отсутствия утечек или результатом физического телефона. Зафиксированные максимумы 116–183ms не скрываются средним значением. Общая машина и состояние окон влияют на cadence.

[memory-two-clients.json](../evidence/memory-two-clients.json) показывает **97% committed memory, 923 MB доступной памяти**, `CommittedBytes=49 460 903 936`, `CommitLimit=50 972 033 024`. Это снимок всего хоста, не память одной игры. На момент отчёта 4/8 native clients **NOT RUN** до освобождения ресурсов; из двухклиентного поведения их результат не выводится. Отказ на 12 клиентов имеет отдельную причину — предел API 0..8, а не этот замер памяти.

## Итоговые свидетельства и завершение

| Набор | Проверенный scope | Итог |
|---|---|---|
| `capacity-probe-result.json` | Фактический запрос 12 native clients | LIMIT: API принимает integer between 0 and 8 |
| `lifecycle/server-outcomes.json` | Максимум два native клиента, production roster/profile, Main off | 27 команд / 147 assertions PASS |
| `production/server-export.json` | Два полных Main-забега на двух native клиентах | 24 trial-player / 4 run-player ledger PASS |
| `production/vote-1.json` | Восемь FireServer-сценариев одного клиента | 8/8 PASS; второй клиент — observer |
| `production/leave-export.json` | Native leave во время Voting/Rule, пустой Main, новый клиент | EmptyReached / ReturnPassed PASS |
| `lifecycle/perf-*.json` | Короткие замеры без работающих опасностей | Данные сохранены; не production benchmark |
| `production/performance-*.json` | Попытка длительного 600 s production-замера | UNAVAILABLE: превышен лимит QA StringValue |

Исправление collector отдельно проверено: offline 901 snapshots × 12 записей игроков, 3604 проверки PASS, максимальный сериализованный блок 11344 bytes; также свежий live smoke около 23 s с 24 значениями на server/client PASS. Это проверка экспорта с ограничением размера; синтетические 12 записей не являются двенадцатью клиентами и не заменяют потерянный production benchmark.

Финальная локальная сборка этой ветки: 26 Luau, ProfileData 59, RuleDeck 22519, ProfileService 27 проверок / 9 сценариев, RuleMath 47, model 490 instances. RuleMath 69 относится к отдельной общей композиции PR2+PR3; результаты разных баз не смешиваются.

Каталог `evidence/` намеренно исключён из Git. Ссылки `../evidence/...` разрешаются в локальном checkout/архиве; исходные данные передаются отдельно в `RuleRoom-QA-evidence-2026-10-23.zip`. GitHub содержит QA-инструменты и отчёт, но не raw evidence; это не ссылки на опубликованные CI-артефакты.

Статусы: PASS — критерий достигнут; FAIL — воспроизведено несоответствие; UNACHIEVED — fixture не достиг цели; LIMIT — ограничение среды; NOT RUN — не запускалось. Complete не заменяет эти статусы. Отсутствие одного клиентского отчёта не считается его успехом.

Финальная среда восстановлена: в родительском Stability возвращены исходные четыре server-модуля и HUD, Main включён, QA-объектов нет. Исходные сеть 500/500 ms, jitter 0 и loss 0.5/0.5% прочитаны обратно. Пользовательские Candidate/WIP не изменялись, публикации Roblox не было. До закрытия обязательных lifecycle/network строк и реального client-count gate полная Stage 2 не заявляется; NPC-нагрузка не закрывает предел 12 клиентов.
