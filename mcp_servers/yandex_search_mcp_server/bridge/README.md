# WS ↔ STDIO Bridge for Yandex Search MCP Server

Этот мост поднимает WebSocket сервер и проксирует JSON‑RPC сообщения к STDIO MCP‑серверу `yandex_search_mcp_server` (stdin/stdout с фреймингом `Content-Length`). Это позволяет приложениям (например, Flutter `sample_app`) подключаться по `ws://`/`wss://` к MCP инструменту `yandex_search_web`.

- Транспорт наружу: WebSocket JSON‑RPC 2.0 (без фрейминга)
- Транспорт внутрь: STDIO JSON‑RPC 2.0 c `Content-Length`
- Инструмент: `yandex_search_web`

## Предпосылки
- Node.js 18+
- Заполненные секреты для Yandex Cloud Search API:
  - `YANDEX_API_KEY`
  - `YANDEX_FOLDER_ID`

Сами переменные читает STDIO‑сервер из `dotenv` или окружения.

## Структура
- `../src/index.js` — STDIO MCP‑сервер (yandex_search_mcp_server)
- `./ws_stdio_bridge.js` — WebSocket мост
- `./package.json` — зависимости моста (`ws`)

## Установка
1) Установите зависимости STDIO‑сервера (один раз):
```
cd ../
npm install
```
2) Установите зависимости моста:
```
cd ./bridge
npm install
```

## Конфигурация секретов
Есть два способа:

1) Через `.env` в каталоге сервера `../`:
```
# файл: mcp_servers/yandex_search_mcp_server/.env
YANDEX_API_KEY=<your_key>
YANDEX_FOLDER_ID=<your_folder_id>
# YANDEX_SEARCH_BASE_URL=https://api.search.yandexcloud.net/v2/web/search (опционально)
# REQUEST_TIMEOUT_MS=15000 (опционально)
```

2) Через переменные окружения (Windows PowerShell пример):
```powershell
$env:YANDEX_API_KEY="<your_key>"
$env:YANDEX_FOLDER_ID="<your_folder_id>"
```

Мост пробрасывает текущее окружение в дочерний процесс STDIO‑сервера.

## Запуск
По умолчанию мост слушает `ws://localhost:8765` и спаунит STDIO‑сервер из каталога `..`.

```powershell
# из каталога bridge
node ws_stdio_bridge.js
```

Порт можно сменить переменной `BRIDGE_PORT`:
```powershell
$env:BRIDGE_PORT="9001"; node ws_stdio_bridge.js
# сервер будет доступен по ws://localhost:9001
```

Ожидаемые логи:
```
[bridge] WS bridge listening on ws://localhost:8765
[bridge] Spawning STDIO MCP server from: .../yandex_search_mcp_server/src/index.js
```

## Проверка вручную (опционально)
Через любой WebSocket клиент (например, `wscat`) подключитесь к `ws://localhost:8765` и отправьте пакет `initialize`:
```
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"test"}}}
```
- Ожидается `result` с `serverInfo` и `capabilities`.

Список инструментов:
```
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
```
Вызов поиска:
```
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"yandex_search_web","arguments":{"query":"test","page":1,"pageSize":5}}}
```

## Интеграция с sample_app
- Клиент: `sample_app/lib/services/mcp_client.dart` (поддерживает `ws://`, `wss://`, а также автоматическую конвертацию `http→ws`, `https→wss`)
- Агент: `sample_app/lib/agents/multi_step_reasoning_agent.dart` (метод `_callMcpSearch`) вызывает `tools/call("yandex_search_web", { queryText|query })`

Шаги:
1) Запустите мост (см. раздел Запуск) и убедитесь, что заданы `YANDEX_API_KEY`/`YANDEX_FOLDER_ID`.
2) В `sample_app` откройте экран Settings и включите “Использовать MCP”.
3) Укажите MCP URL: `ws://localhost:8765` (или ваш порт). Можно указать `http://localhost:8765` — будет автоматически сконвертировано в `ws://`.
4) Откройте экран “Многоэтапный” и задайте запрос с поиском, например: «Найди последние новости по Yandex GPT».
5) При успешном вызове инструмента в AppBar появится индикатор MCP использования.

## Частые проблемы и решения
- "only ws: and wss: schemes are supported":
  - Убедитесь, что URL в Settings начинается с `ws://`/`wss://` или `http://`/`https://` (конвертируется автоматически в клиенте);
  - Проверьте, что мост запущен и порт корректный.
- Ошибка линковки/порт занят:
  - Смените порт через `BRIDGE_PORT` и обновите URL в Settings.
- 401/403 от Yandex Search:
  - Проверьте `YANDEX_API_KEY` и `YANDEX_FOLDER_ID`.
- Таймауты `REQUEST_TIMEOUT_MS`:
  - Увеличьте значение в `.env` (сервер) или `timeout` на стороне клиента/агента (если нужно).

## Безопасность
- Не коммитьте реальные ключи в репозиторий.
- Используйте `.env` (он игнорируется git) или секреты окружения.
- Ограничьте доступ к мосту (локальный порт/файрвол) — мост принимает подключения без аутентификации.

## Лицензия
MIT
