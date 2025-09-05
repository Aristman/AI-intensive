# Yandex Search MCP Server (STDIO, ESM)

STDIO MCP-сервер для интеграции с Yandex Search API.

- Транспорт: stdin/stdout, JSON-RPC 2.0, фрейминг `Content-Length`.
- Инструменты: `yandex_search_web` — синхронный веб‑поиск.
- Аутентификация: `Authorization: Api-Key <YANDEX_API_KEY>` + `x-folder-id: <YANDEX_FOLDER_ID>`.
- Логи/ошибки — только в stderr.

## Структура
- `src/index.js` — точка входа, STDIO цикл, роутинг JSON‑RPC.
- `src/config.js` — конфигурация/валидация окружения.
- `src/utils.js` — фрейминг и JSON‑RPC утилиты.
- `src/handlers/tools.js` — инструменты (`tools/list`, `tools/call`).
- `src/handlers/resources.js` — ресурсы (`resources/list`, `resources/read`, заглушки).
- `Roadmap.md` — чеклист задач.

## Организация транспорта
Сервер поддерживает два режима коммуникации:

### STDIO транспорт (основной)
- **Протокол:** JSON-RPC 2.0 с фреймингом `Content-Length`.
- **Вход/выход:** stdin/stdout.
- **Запуск:** `npm start` или `node ./src/index.js`.
- **Применение:** Для локального запуска MCP сервера в качестве дочернего процесса.
- **Пример:** Используется в интеграциях с приложениями, где сервер запускается как процесс (например, в Flutter через Process).

### WebSocket транспорт (через bridge)
- **Протокол:** JSON-RPC 2.0 без фрейминга.
- **Вход/выход:** WebSocket соединение (ws:// или wss://).
- **Запуск:** `cd bridge && node ws_stdio_bridge.js`.
- **Применение:** Для удаленного доступа или интеграции с приложениями, поддерживающими WebSocket.
- **Пример:** Используется в `sample_app` для подключения к MCP серверу по сети.
- **Конфигурация:** Порт по умолчанию 8765, изменяется через `BRIDGE_PORT`.

Bridge спаунит STDIO сервер и проксирует сообщения между WebSocket и STDIO.

## Переменные окружения
- `YANDEX_API_KEY` — обязательно.
- `YANDEX_FOLDER_ID` — обязательно.
- `YANDEX_SEARCH_BASE_URL` — опционально (по умолчанию `https://api.search.yandexcloud.net/v2/web/search`).
- `REQUEST_TIMEOUT_MS` — опционально, по умолчанию 15000.

## Настройка .env
- Скопируйте файл `.env.example` в `.env` и заполните значения:
```
cp .env.example .env
# Затем отредактируйте .env и укажите YANDEX_API_KEY/YANDEX_FOLDER_ID
```

## Установка зависимостей
В корне модуля выполните установку (создаст `node_modules/`):
```
npm install
```

Windows PowerShell пример:
```powershell
$env:YANDEX_API_KEY="<your-key>"
$env:YANDEX_FOLDER_ID="<your-folder-id>"
node .\src\index.js
```

## Пример обмена (ручная проверка)
Отправьте в stdin:
```
Content-Length: 86

{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"clientInfo":{"name":"test"}}}
```
Ответ в stdout:
```
Content-Length: 176

{"jsonrpc":"2.0","id":"1","result":{"serverInfo":{"name":"yandex_search_mcp","version":"0.1.0"},"capabilities":{"tools":{},"resources":{}}}}
```

Список инструментов:
```
Content-Length: 64

{"jsonrpc":"2.0","id":"2","method":"tools/list","params":{}}
```

Вызов поиска:
```
Content-Length: 145

{"jsonrpc":"2.0","id":"3","method":"tools/call","params":{"name":"yandex_search_web","arguments":{"query":"test","page":1,"pageSize":5}}}
```

## Замечания
- Параметры и схема ответа Yandex Search могут отличаться — реализован безопасный фоллбэк и TODO на уточнение.
- Реализованы ретраи по 5xx/сетевым ошибкам с экспоненциальной паузой (см. `withRetries`).
- TODO: пагинация/нормализация результатов, кэш.
- Безопасность: не храните реальные секреты в `.env.example` — используйте `.env` (он игнорируется Git). 
