# Telegram MCP Server (Python, STDIO) / Телеграм MCP сервер (Python, STDIO)

## Русская версия

Python-реализация сервера Model Context Protocol (MCP) для Telegram на базе Telethon.
Сервер общается по STDIO с JSON-RPC фреймингом (по заголовку Content-Length).
Строгое правило: stdout зарезервирован только под MCP-кадры, все логи печатаются в stderr (во избежание порчи протокола).

Этот сервер — Python-эквивалент ранее существовавшего Node.js сервера в `mcp_servers/telegram_mcp_server/`,
совместимый с клиентами, которые ожидают методы:
- `initialize`
- `tools/list`
- `tools/call`
- `resources/list` (плейсхолдер)
- `resources/read` (плейсхолдер)

Директория: `mcp_servers/telegram_mcp_server_py/`

- `main.py` — STDIO MCP сервер.
- `tools.py` — инструменты Telegram на Telethon.
- `utils.py` — инициализация Telegram-клиента (бот/пользователь через session.txt), сохранение сессии.
- `resources.py` — обработчики ресурсов (сейчас плейсхолдеры, как и в Node-версии).
- `config.py` — загрузка переменных окружения и валидация.
- `cli_login.py` — отдельная CLI-утилита для интерактивного получения/обновления Telegram-сессии.
- `requirements.txt` — зависимости Python.

### Возможности

- Транспорт STDIO с разделением stdout (MCP) и stderr (логи).
- Интеграция с Telegram через Telethon; поддержка бота (token) и пользовательской сессии (session.txt).
- Совместимый формат ответов для `tools/call`: JSON заворачивается в `{ content: [{ type: 'text', text: '...json...' }] }`.
- Набор инструментов соответствует Node-варианту в этом репозитории (см. ниже).

### Требования

- Python 3.9+
- Установка зависимостей:

```bash
pip install -r mcp_servers/telegram_mcp_server_py/requirements.txt
```

### Переменные окружения (.env)

Файл `.env` рядом с сервером (`mcp_servers/telegram_mcp_server_py/.env`) или переменные окружения процесса.

- Для бота (рекомендуется):
  - `TELEGRAM_BOT_TOKEN`
- Для пользователя (MTProto; требуется заранее созданная сессия):
  - `TELEGRAM_API_ID`
  - `TELEGRAM_API_HASH`
  - `TELEGRAM_PHONE_NUMBER`
- Опционально:
  - `TELEGRAM_SESSION_FILE` — путь к файлу сессии (по умолчанию `mcp_servers/telegram_mcp_server_py/session.txt`).

Важно: сам сервер не выполняет интерактивный логин (stdin занят MCP). Для создания/обновления сессии используйте `cli_login.py` (см. ниже).

### Запуск сервера (вручную)

Запускайте как модуль Python с неблокируемым выводом:

- PowerShell (Windows):

```powershell
python -u -m mcp_servers.telegram_mcp_server_py.main
```

- Bash:

```bash
python3 -u -m mcp_servers.telegram_mcp_server_py.main
```

Сервер читает/пишет MCP-сообщения через stdin/stdout. Все логи идут в stderr.

### Использование с `telegram_monitoring_agent`

Файл `telegram_monitoring_agent/src/mcp_client.py` уже настроен на запуск этого сервера по умолчанию через команду:

```
"{sys.executable}" -u -m mcp_servers.telegram_mcp_server_py.main
```

Дополнительной настройки не требуется, если структура репозитория сохранена, а зависимости сервера установлены в ту же Python-среду, что и агент.

### Интерактивный логин (CLI)

Отдельная утилита для интерактивного логина и сохранения `session.txt`:

```bash
# Логин бота (рекомендуется)
python -m mcp_servers.telegram_mcp_server_py.cli_login --bot-token "<TELEGRAM_BOT_TOKEN>" [--session-file path]

# Логин пользователя (потребует код и, возможно, пароль 2FA)
python -m mcp_servers.telegram_mcp_server_py.cli_login --api-id <ID> --api-hash <HASH> --phone <PHONE> [--session-file path]
```

Можно использовать `.env` рядом с сервером (`mcp_servers/telegram_mcp_server_py/.env`):

```
TELEGRAM_BOT_TOKEN=...
# или
TELEGRAM_API_ID=...
TELEGRAM_API_HASH=...
TELEGRAM_PHONE_NUMBER=...
# опционально
TELEGRAM_SESSION_FILE=D:\\path\\to\\session.txt
```

После успешного входа CLI сохранит строку сессии в `session.txt` (или по указанному пути). Сервер переиспользует её без интерактива.

### MCP протокол (STDIO фрейминг)

JSON-RPC сообщения инкапсулируются заголовком и телом в UTF-8:

```
Content-Length: <bytes>\r\n
\r\n
{ "jsonrpc": "2.0", ... }
```

- Сервер пишет кадры только в stdout.
- Сервер печатает логи в stderr (никогда в stdout), чтобы не портить MCP-поток.

#### Поддерживаемые методы

- `initialize`, `tools/list`, `tools/call`, `resources/*` — формат полностью совместим с Node-версией (см. английскую секцию ниже для JSON-примеров).

### Инструменты

Сервер предоставляет следующие инструменты (имена и аргументы совместимы с Node-версией в этом репо):

1. `tg.resolve_chat`
   - Args: `input` | `chat` | `chatId`
   - Returns: `{ id, username, title, type }`

2. `tg.fetch_history` (alias of `tg.read_messages`)
   - Args: `chat`, `page_size` (or `limit`), `min_id` (or `minId`), `max_id` (or `MaxId`)
   - Returns: `{ messages: [{ id, text, date, from: { id, display } }] }`

3. `tg.read_messages`
   - Args: `chat`, `page_size` (or `limit`), `min_id` (or `minId`), `max_id` (or `maxId`)
   - Returns: same as above

4. `tg.send_message`
   - Args: `chat`, `message` (or `text`)
   - Returns: `{ message_id }`

5. `tg.forward_message`
   - Args: `from_chat` (or `fromChatId`), `to_chat` (or `toChatId`), `message_id` (or `messageId`)
   - Returns: `{ forwarded_id }`

6. `tg.mark_read`
   - Args: `chat`, `message_ids` (or `messageIds`)
   - Returns: `{ success: true }`

7. `tg.get_unread_count`
   - Args: optional `chat`
   - Returns: `{ unread }`

8. `tg.get_chats`
   - Args: none
   - Returns: `[{ id, title, username, unread }]`

Примечание: В другом сервере (`mcp_server/`) ранее использовались `tg_send_message`, `tg_send_photo`, `tg_get_updates`.
Текущий Python-сервер повторяет набор из `mcp_servers/telegram_mcp_server/`. Если нужны указанные инструменты — быстро добавлю.

---

## English version

A Python implementation of a Model Context Protocol (MCP) server for Telegram using Telethon. 
The server communicates over STDIO with JSON-RPC framing (Content-Length based), reserving stdout for MCP frames and printing all logs to stderr.

This is a Python counterpart to the earlier Node.js server located at `mcp_servers/telegram_mcp_server/`, designed for drop-in compatibility with clients that expect:
- `initialize`
- `tools/list`
- `tools/call`
- `resources/list` (stub)
- `resources/read` (stub)

Directory: `mcp_servers/telegram_mcp_server_py/`

- `main.py` — MCP server over stdio.
- `tools.py` — Telegram tools backed by Telethon.
- `utils.py` — Telegram client setup (bot or user via session.txt), session persistence.
- `resources.py` — resource handlers (currently placeholders, as in Node version).
- `config.py` — env loading and validation.
- `cli_login.py` — standalone interactive CLI for obtaining/updating Telegram session.
- `requirements.txt` — Python dependencies.

## Features

- STDIO transport with strict separation of stdout (MCP frames) and stderr (logs).
- Telethon-based Telegram integration; supports both bot token and user session.
- Compatible responses for MCP `tools/call` (wraps JSON into `{ content: [{ type: 'text', text: '...json...' }] }`).
- Tools parity with Node variant in this repo (see Tooling below).

## Requirements

- Python 3.9+
- Installed dependencies:

```bash
pip install -r mcp_servers/telegram_mcp_server_py/requirements.txt
```

## Environment Variables (.env)

Create a `.env` file next to the server (`mcp_servers/telegram_mcp_server_py/.env`) or pass vars via process environment. Supported variables:

- For bot authentication (recommended):
  - `TELEGRAM_BOT_TOKEN`
- For user authentication (MTProto; requires pre-created session):
  - `TELEGRAM_API_ID`
  - `TELEGRAM_API_HASH`
  - `TELEGRAM_PHONE_NUMBER`
- Optional:
  - `TELEGRAM_SESSION_FILE` — path to session file (defaults to `mcp_servers/telegram_mcp_server_py/session.txt`).

Note: The server process itself does not perform interactive login (to keep MCP stdin clean). Use `cli_login.py` to create/update the session, see below.

## Running the server (manually)

Run as a Python module with unbuffered stdio:

- Windows PowerShell:

```powershell
python -u -m mcp_servers.telegram_mcp_server_py.main
```

- Bash:

```bash
python3 -u -m mcp_servers.telegram_mcp_server_py.main
```

The server reads/writes MCP messages via stdout/stdin. All logs go to stderr.

## Using with telegram_monitoring_agent

`telegram_monitoring_agent/src/mcp_client.py` is configured to start this server by default via:

```
"{sys.executable}" -u -m mcp_servers.telegram_mcp_server_py.main
```

No extra setup is required if you keep the repository structure intact and install the server dependencies in the same Python environment used by the agent.

## Interactive Login (CLI utility)

Since the server uses stdin/stdout for MCP frames, interactive login lives in a separate CLI:

- Run with arguments:

```bash
# Bot login (recommended)
python -m mcp_servers.telegram_mcp_server_py.cli_login --bot-token "<TELEGRAM_BOT_TOKEN>" [--session-file path]

# User login (requires code and possibly 2FA password)
python -m mcp_servers.telegram_mcp_server_py.cli_login --api-id <ID> --api-hash <HASH> --phone <PHONE> [--session-file path]
```

- Or use `.env` next to the server (`mcp_servers/telegram_mcp_server_py/.env`):

```
TELEGRAM_BOT_TOKEN=...
# or
TELEGRAM_API_ID=...
TELEGRAM_API_HASH=...
TELEGRAM_PHONE_NUMBER=...
# optional
TELEGRAM_SESSION_FILE=D:\\path\\to\\session.txt
```

Then just run:

```bash
python -m mcp_servers.telegram_mcp_server_py.cli_login
```

On success, the CLI saves a session string to `session.txt` (or the path you specified). The server will reuse it non-interactively.

## MCP Protocol (STDIO framing)

JSON-RPC messages are framed with headers followed by a blank line and a UTF-8 JSON body:

```
Content-Length: <bytes>\r\n
\r\n
{ "jsonrpc": "2.0", ... }
```

- The server only writes frames to stdout.
- The server prints logs to stderr (never stdout) to avoid corrupting the MCP stream.

### Supported Methods

- `initialize`
  - Request:
    ```json
    {
      "jsonrpc": "2.0",
      "id": 1,
      "method": "initialize",
      "params": {
        "protocolVersion": "2024-09-18",
        "clientInfo": {"name": "<client>", "version": "<ver>"},
        "capabilities": {"tools": {}, "resources": {}, "prompts": {}}
      }
    }
    ```
  - Response:
    ```json
    {
      "jsonrpc": "2.0",
      "id": 1,
      "result": {
        "protocolVersion": "2024-09-18",
        "serverInfo": {"name": "telegram-mcp-server", "version": "0.1.0"},
        "capabilities": {"tools": {}, "resources": {}, "prompts": {}}
      }
    }
    ```

- `tools/list`
  - Response result:
    ```json
    { "tools": [ {"name": "tg.read_messages", "description": "...", "inputSchema": {...}}, ... ] }
    ```

- `tools/call`
  - Request params: `{ "name": "<toolName>", "arguments": { ... } }`
  - Response result:
    ```json
    { "content": [ { "type": "text", "text": "{...JSON...}" } ] }
    ```

- `resources/list` — returns `{ "resources": [] }` (placeholder)
- `resources/read` — returns a JSON content wrapper (placeholder)

## Tools

The server exposes the following tools (names and argument compatibility match the Node.js server in this repo):

1. `tg.resolve_chat`
   - Args: `input` | `chat` | `chatId`
   - Returns: `{ id, username, title, type }`

2. `tg.fetch_history` (alias of `tg.read_messages`)
   - Args: `chat`, `page_size` (or `limit`), `min_id` (or `minId`), `max_id` (or `maxId`)
   - Returns: `{ messages: [{ id, text, date, from: { id, display } }] }`

3. `tg.read_messages`
   - Args: `chat`, `page_size` (or `limit`), `min_id` (or `minId`), `max_id` (or `maxId`)
   - Returns: same as above

4. `tg.send_message`
   - Args: `chat`, `message` (or `text`)
   - Returns: `{ message_id }`

5. `tg.forward_message`
   - Args: `from_chat` (or `fromChatId`), `to_chat` (or `toChatId`), `message_id` (or `messageId`)
   - Returns: `{ forwarded_id }`

6. `tg.mark_read`
   - Args: `chat`, `message_ids` (or `messageIds`)
   - Returns: `{ success: true }`

7. `tg.get_unread_count`
   - Args: optional `chat`
   - Returns: `{ unread }`

8. `tg.get_chats`
   - Args: none
   - Returns: `[{ id, title, username, unread }]`

Note: In previous tasks, a different server (`mcp_server/`) included `tg_send_message`, `tg_send_photo`, `tg_get_updates`. This Python server replicates the toolset from `mcp_servers/telegram_mcp_server/`. If you need those extra tools here, we can add them quickly.

## Logging & Debugging

- All logs are printed to stderr.
- The agent (`telegram_monitoring_agent`) waits for the readiness message on stderr:
  - `"Telegram client ready, tools registered."`
- If you see `Tools not ready` in responses, ensure the Telegram credentials are valid and the session exists (for user auth, run `cli_login.py` to create session).

## Troubleshooting

- "Interactive authorization required" — create/update `session.txt` with `cli_login.py`.
- "Unknown tool" — check the tool name; call `tools/list` to see what’s available.
- No response / framing issues — ensure stdout is not used for logs. Only stderr should contain logs.
- Windows newline quirks — framing uses `\r\n\r\n`; this is handled by the server. Use `-u` (unbuffered) mode as shown above.

## License

This submodule follows the repository’s main license.
