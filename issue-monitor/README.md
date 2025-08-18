# Issue Monitor (Kotlin)

Фоновое приложение, работающее на VPS, которое:
- Периодически опрашивает MCP‑сервер (`mcp_server/`) методом `get_repo` и получает число открытых issues в репозитории GitHub (`Aristman/AI-intensive` по умолчанию)
- Отправляет уведомление в Telegram с текущим количеством открытых задач и списком последних issues

## Архитектура
- MCP клиент: WebSocket + JSON‑RPC 2.0 (`tools/call get_repo`, `tools/call list_issues`)
- Уведомления: через MCP инструмент `tg_send_message` (бот и дефолтный чат настраиваются на стороне сервера — `TELEGRAM_DEFAULT_CHAT_ID`)
- Конфигурация: через переменные окружения или `config.properties`

Ключевые файлы:
- `src/main/kotlin/ru/marslab/issuemonitor/service/IssueMonitorService.kt`
- `src/main/kotlin/ru/marslab/issuemonitor/mcp/McpClient.kt`
- `src/main/kotlin/ru/marslab/issuemonitor/notify/TelegramNotifier.kt`
- `src/main/kotlin/ru/marslab/issuemonitor/Main.kt`

## Требования
- JDK 17+
- Запущенный MCP‑сервер (`mcp_server/` в корне репозитория)
  - Сконфигурирован `.env` (см. `mcp_server/README.md`)
  - Запуск: `npm start` (по умолчанию `ws://localhost:3001`)

## Сборка
```powershell
# из корня репозитория
.\gradlew.bat :issue-monitor:build -x test
# fat‑jar: build\libs\issue-monitor-1.0.0-all.jar
```
Linux/macOS:
```bash
./gradlew :issue-monitor:build -x test
```

## Конфигурация
Можно задать через переменные окружения ИЛИ через `config.properties` (укажите путь через `CONFIG_FILE=/path/config.properties`).

Поддерживаемые параметры:
- MCP_WS_URL (по умолчанию `ws://localhost:3001`)
- GITHUB_OWNER (по умолчанию `Aristman`)
- GITHUB_REPO (по умолчанию `AI-intensive`)
- POLL_INTERVAL_SECONDS (по умолчанию `3600`)
- SEND_ALWAYS (по умолчанию `false`) — отправлять сообщение каждый цикл, даже если число не изменилось
- ISSUES_LIST_LIMIT (по умолчанию `5`) — сколько последних открытых issues включать в сообщение
- TELEGRAM_ENABLED (по умолчанию `true`)
- TELEGRAM_BOT_TOKEN — токен бота (как правило, не требуется в клиенте, т.к. используется MCP)
- TELEGRAM_CHAT_ID — id чата/канала (можно не задавать, если в MCP сервере задан `TELEGRAM_DEFAULT_CHAT_ID`)

Пример `issue-monitor/config.properties.sample`:
```
MCP_WS_URL=ws://127.0.0.1:3001
GITHUB_OWNER=aristman
GITHUB_REPO=AI-intensive
POLL_INTERVAL_SECONDS=1800
SEND_ALWAYS=true
ISSUES_LIST_LIMIT=5
TELEGRAM_ENABLED=true
# Ниже обычно не требуется, если на MCP сервере задан TELEGRAM_DEFAULT_CHAT_ID и TELEGRAM_BOT_TOKEN
# TELEGRAM_BOT_TOKEN=123456:ABCDEF_your_token_here
# TELEGRAM_CHAT_ID=123456789
```

Как получить TELEGRAM_CHAT_ID:
- Напишите сообщение вашему боту в ЛС/группе
- Выполните:
  - Через API: `https://api.telegram.org/bot<ТОКЕН>/getUpdates` и найдите поле `chat.id`
  - Или используйте @getidsbot / @userinfobot

## Запуск
Windows (PowerShell):
```powershell
$env:CONFIG_FILE = "D:/apps/issue-monitor/config.properties"
# Интервал можно переопределить параметром в секундах:
# варианты: --interval=180, --interval 180, либо позиционный 180
java -jar issue-monitor/build/libs/issue-monitor-1.0.0-all.jar --interval=180
```
Linux:
```bash
export CONFIG_FILE=/opt/issue-monitor/config.properties
# Аналогично можно задать интервал при запуске
java -jar issue-monitor/build/libs/issue-monitor-1.0.0-all.jar 180
```

## systemd unit (Linux)
`/etc/systemd/system/issue-monitor.service`:
```
[Unit]
Description=Issue Monitor (AI-intensive)
After=network-online.target

[Service]
User=youruser
WorkingDirectory=/opt/AI-intensive
Environment=CONFIG_FILE=/opt/issue-monitor/config.properties
ExecStart=/usr/bin/java -jar /opt/AI-intensive/issue-monitor/build/libs/issue-monitor-1.0.0-all.jar --interval=180
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```
Команды:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now issue-monitor
sudo systemctl status issue-monitor
```

## Примечания
- Приложение толерантно к временным ошибкам MCP/сети: в случае ошибок делает паузу и повторяет попытку.
- Для корректной работы MCP‑сервера обязательно укажите `GITHUB_TOKEN`, `TELEGRAM_BOT_TOKEN` и (рекомендуется) `TELEGRAM_DEFAULT_CHAT_ID` в его `.env` (см. `mcp_server/README.md`).

## Деплой на удалённый сервер
В каталоге `issue-monitor/` есть скрипты деплоя, которые копируют приложение на сервер с помощью `ssh/scp`.

- Назначение по умолчанию: `ai-intensive/issue-monitor`
- Копируется: последний fat‑jar из `build/libs/*-all.jar`, а также (при наличии) `README.md`, `config.properties` и `.env`

Linux/macOS:
```bash
./gradlew :issue-monitor:build -x test
./issue-monitor/deploy.sh user@your-host                      # в ai-intensive/issue-monitor
./issue-monitor/deploy.sh user@your-host /opt/ai-intensive/issue-monitor  # в указанный путь
```

Windows (PowerShell):
```powershell
.\gradlew.bat :issue-monitor:build -x test
powershell -ExecutionPolicy Bypass -File .\issue-monitor\deploy.ps1 -Server user@your-host
powershell -ExecutionPolicy Bypass -File .\issue-monitor\deploy.ps1 -Server user@your-host -DestPath /opt/ai-intensive/issue-monitor
```

После копирования запустить на сервере (пример):
```bash
ssh user@your-host 'cd ai-intensive/issue-monitor && nohup java -jar issue-monitor-*-all.jar --interval=180 > app.log 2>&1 & disown'
```

Альтернатива: запуск через скрипты с подхватом переменных из `.env` и передачей аргументов
```bash
# Linux/macOS
ssh user@your-host 'cd ai-intensive/issue-monitor && ./start.sh'                         # использует ./\.env
ssh user@your-host 'cd ai-intensive/issue-monitor && ./start.sh /path/to/.env -- --interval=180'
# запуск в фоне (daemon):
ssh user@your-host 'cd ai-intensive/issue-monitor && ./start.sh -d -- --interval=180'    # nohup, логи в issue-monitor.log, PID в issue-monitor.pid

# Windows (PowerShell на сервере Windows)
powershell -ExecutionPolicy Bypass -File .\issue-monitor\start.ps1                      # использует .\.env
powershell -ExecutionPolicy Bypass -File .\issue-monitor\start.ps1 -EnvPath C:\\path\\to\\.env -- --interval=180
# запуск в фоне (daemon):
powershell -ExecutionPolicy Bypass -File .\issue-monitor\start.ps1 -Background -- --interval=180
```

### Остановка

```bash
# Linux/macOS
./stop.sh

# Windows PowerShell
powershell -ExecutionPolicy Bypass -File .\stop.ps1
```

### Установка как systemd-сервис (Linux)

Скрипт `install-systemd.sh` создаёт сервис и сразу запускает его. Можно передать дополнительные аргументы приложению через `--args`.

```bash
ssh user@your-host 'cd ai-intensive/issue-monitor && sudo ./install-systemd.sh \
  --name ai-intensive-issue-monitor \
  --user $USER \
  --env /path/to/.env \
  --args "--interval=180"'

# Управление
sudo systemctl status ai-intensive-issue-monitor
sudo systemctl restart ai-intensive-issue-monitor
sudo systemctl stop ai-intensive-issue-monitor
sudo systemctl disable ai-intensive-issue-monitor

# Логи
tail -f ai-intensive/issue-monitor/issue-monitor.log
```

### Удаление systemd‑сервиса (Linux)

```bash
ssh user@your-host 'cd ai-intensive/issue-monitor && sudo ./uninstall-systemd.sh --name ai-intensive-issue-monitor'
```
