# Obsidian для RuleRoom

Vault находится в [docs/obsidian-vault](../obsidian-vault/README.md) внутри существующего репозитория boblox. Начальная заметка — [Dashboard](../obsidian-vault/00-Dashboard/Dashboard.md). Это документация проекта, не второй игровой checkout. Community plugins, Sync и Publish не требуются.

## Один источник истины

Код `src/`, `tools/build_assets.py` и Rojo mapping определяют игру. Канонические [Roadmap](../obsidian-vault/07-Tasks/Roadmap.md) и [Release Checklist](<../obsidian-vault/10-Releases/Release Checklist.md>) перенесены в vault; прежние `docs/ROADMAP.md` и `docs/RELEASE_CHECKLIST.md` служат указателями. Не вести второй список статусов. Исторические QA-отчёты сохраняют дату, версию и границы доказательств.

Каталог `09-AI-Skills` ведёт отдельный генератор/владелец. Остальные заметки редактируются как обычный Markdown; автоматическая генерация не должна перезаписывать авторские записи. `.obsidian` содержит локальные настройки конкретного пользователя, исключённые из Git; глобальные настройки и личные vault не копируются.

## Установка и открытие

24 октября 2026 реестр Windows и свойства файла подтвердили Obsidian **1.12.7** в `D:\obsidian\Obsidian.exe`; рядом существует `Obsidian.com` — штатный Windows terminal redirector. Отсутствие команды в текущем PATH не означает отсутствие программы. Это локальные пути данного компьютера, а не обязательные пути на чужой машине.

В vault manager выбрать **Open folder as vault** и указать папку `docs/obsidian-vault` этого checkout. Затем открыть `00-Dashboard/Dashboard.md`. Другие личные vault не использовать для проекта. После регистрации папки можно вызвать:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\obsidian\Open-Vault.ps1
```

Скрипт строит документированный [Obsidian URI](https://obsidian.md/help/uri) к Dashboard; он не читает заметки других vault и не регистрирует папку обходным редактированием global JSON.

## Native CLI

Официальная [инструкция CLI](https://obsidian.md/help/cli) требует installer 1.12.7+ и включение **Settings → General → Command line interface**, затем штатную регистрацию команды. После изменения PATH нужен новый терминал. На Windows используйте `Obsidian.com`, если команда ещё не находится через PATH. Работающая desktop-программа необходима.

Сначала откройте именно проектный vault. Каждую команду адресуйте явно: `vault=<name>` или `vault=<id>` ставится **перед** командой. Не выполнять `read`, `create`, `append`, `eval` без выбранного vault: по умолчанию они могут обратиться к активному личному vault. Здесь не нужны developer eval/CDP или сторонние MCP-плагины.

```powershell
# Только после открытия проектной папки и включения CLI.
& 'D:\obsidian\Obsidian.com' vault=obsidian-vault vault info=path
& 'D:\obsidian\Obsidian.com' vault=obsidian-vault read path=00-Dashboard/Dashboard.md
& 'D:\obsidian\Obsidian.com' vault=obsidian-vault unresolved total
```

При нескольких vault с одинаковым именем использовать ID, полученный из metadata зарегистрированной проектной папки. До любой записи сверить `vault info=path` с абсолютным путём проекта. Пароли, содержимое личных notes и изменение глобальных настроек напрямую для настройки не нужны.

После GUI-настройки воспроизводимый native smoke: `python tools/obsidian/verify_cli.py`. Скрипт находит в регистрационной metadata только точный путь этого проекта, передаёт его ID каждой команде и сначала сверяет `vault info=path`. Затем читает Dashboard, создаёт уникальную временную заметку через CLI, читает её тем же CLI и удаляет только свой неизменённый файл. Без зарегистрированного проектного vault он завершает работу до запуска CLI.

## Проверка файлов и навигации

Из корня репозитория:

```powershell
python tools/obsidian/verify_vault.py
python tools/obsidian/verify_vault.py --write-smoke
```

Проверяются все 11 папок, существование и однозначность wikilink-целей, локальные Markdown-ссылки. Не проверяются веб-доступность, heading anchors, внешний вид Obsidian или понимание текста. `--write-smoke` создаёт эксклюзивную временную UTF-8 заметку только в Dashboard, читает её и удаляет ровно этот созданный файл. Существующие заметки не перезаписываются.

## Фактически проверено 24 октября 2026

Проектная папка открыта через GUI как отдельный vault; оператор включил General → Command line interface и выполнил Register. Native `version` вернул `1.12.7 (installer 1.12.7)`. Скрипт `verify_cli.py` подтвердил точный проектный путь, прочитал Dashboard, создал и прочитал уникальную заметку через CLI; временный файл удалён. Первоначальный пробник с точкой в начале имени не вернулся через `read`; после перехода на обычное видимое уникальное имя полный smoke прошёл. Первый неуспешный результат не объявлялся успешным.

`verify_vault.py --write-smoke` подтвердил отдельный файловый UTF-8 round trip и удаление пробника. Проверка валидатора обнаруживает пропущенные wiki/Markdown цели, неоднозначные имена и выход wikilink за границы vault; fenced code examples не принимаются за навигацию. Python-компиляция и PowerShell AST для Open-Vault прошли.

После добавления каталога skills итог: **20 notes, 11 обязательных папок, 91 wikilink, 0 errors, 0 orphans**. Native CLI ответил `No unresolved links found.` Повторный native create/read PASS, временных `.qa-*`/`QA-CLI-*` файлов в Dashboard не осталось. Машинная сводка — [obsidian-verification.json](obsidian-verification.json).

Obsidian считает относительные ссылки за пределы vault внутренними отсутствующими целями. Поэтому заметки ссылаются на исходный код и прежние документы через закреплённый GitHub baseline `afdbc08` и указывают локальные repo paths. Внутренние связи остаются wikilinks. Новые ещё не опубликованные файлы указываются путями репозитория, без ложных публичных URL. CLI smoke доказывает работу интерфейса команд и файлового доступа; он не является оценкой удобства интерфейса или игровой приёмкой.
