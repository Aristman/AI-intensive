# Issue Monitor (Kotlin)

Фоновое приложение, работающее на VPS, которое:
- Периодически опрашивает MCP‑сервер (`mcp_server/`) методом `get_repo` и получает число открытых issues в репозитории GitHub (`Aristman/AI-intensive` по умолчанию)
- Отправляет уведомление в Telegram с текущим количеством открытых задач

## Архитектура
- MCP клиент: WebSocket + JSON‑RPC 2.0 (`tools/call get_repo`)
- Уведомления: Telegram Bot API `sendMessage`
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
- TELEGRAM_ENABLED (по умолчанию `true`)
- TELEGRAM_BOT_TOKEN — токен бота
- TELEGRAM_CHAT_ID — id чата/канала для отправки

Пример `issue-monitor/config.properties.sample`:
```
MCP_WS_URL=ws://127.0.0.1:3001
GITHUB_OWNER=aristman
GITHUB_REPO=AI-intensive
POLL_INTERVAL_SECONDS=1800
SEND_ALWAYS=false
TELEGRAM_ENABLED=true
TELEGRAM_BOT_TOKEN=123456:ABCDEF_your_token_here
TELEGRAM_CHAT_ID=123456789
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
java -jar issue-monitor/build/libs/issue-monitor-1.0.0-all.jar
```
Linux:
```bash
export CONFIG_FILE=/opt/issue-monitor/config.properties
java -jar issue-monitor/build/libs/issue-monitor-1.0.0-all.jar
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
ExecStart=/usr/bin/java -jar /opt/AI-intensive/issue-monitor/build/libs/issue-monitor-1.0.0-all.jar
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
- Для корректной работы MCP‑сервера обязательно укажите `GITHUB_TOKEN` в его `.env` (см. `mcp_server/README.md`).
