# MCP Server (GitHub + Telegram)

Лёгкий MCP-сервер (WebSocket + JSON-RPC 2.0), предоставляющий инструменты GitHub и Telegram, доступные через JSON-RPC по WebSocket.

Server Info: name = `mcp-github-telegram-server`

## Возможности
- Инструменты MCP:
  - `get_repo(owner, repo)` — получить информацию о репозитории GitHub
  - `search_repos(query)` — поиск репозиториев GitHub
  - `create_issue(owner, repo, title, body?)` — создать GitHub Issue
  - `list_issues(owner, repo, state?, per_page?, page?)` — список issues репозитория. Возвращает только issues (PR исключены). Аргументы по умолчанию: `state = "open"`, `per_page = 5`, `page = 1`.
  - `create_release(owner, repo, tag_name, name?, body?, draft?, prerelease?, target_commitish?)` — создать GitHub релиз
  - `list_pull_requests(owner, repo, state?, per_page?, page?)` — список Pull Requests
  - `get_pull_request(owner, repo, number)` — детали конкретного PR
  - `list_pr_files(owner, repo, number, per_page?, page?)` — файлы, изменённые в PR
  - `tg_send_message(chat_id?, text, parse_mode?, disable_web_page_preview?)` — отправить текстовое сообщение в Telegram.
  - `tg_send_photo(chat_id?, photo, caption?, parse_mode?)` — отправить фото в Telegram.
  - `tg_get_updates(offset?, timeout?, allowed_updates?)` — получить обновления (long polling) в Telegram.
  - `create_issue_and_notify(owner, repo, title, body?, chat_id?, message_template?)` — создать issue и отправить уведомление в Telegram.
  - `docker_start_java(container_name?, image?, port?, extra_args?)` — запустить или создать+запустить локальный контейнер с JDK (по умолчанию образ `eclipse-temurin:20-jdk`, порт пробрасывается на 8080).
- WebSocket JSON-RPC 2.0 интерфейс: методы `initialize`, `tools/list`, `tools/call`
- Токен GitHub хранится только на сервере (безопасно)

## Требования
- Node.js (LTS), npm

## Установка
```powershell
# из каталога mcp_server
npm install
```

## Конфигурация окружения (.env)
Создайте файл `.env` из шаблона `.env.example` и заполните значения:
```env
GITHUB_TOKEN=ghp_xxx   # персональный токен, достаточные права для создания issues
PORT=3001              # порт WebSocket сервера (по умолчанию 3001)
TELEGRAM_BOT_TOKEN=xxx # Telegram Bot API токен
TELEGRAM_DEFAULT_CHAT_ID=xxx # (рекомендуется) чат по умолчанию для отправки сообщений
```
Рекомендации по токену:
- Подходит classic с scope `repo` (или `public_repo` для публичных репозиториев),
- Либо fine‑grained с разрешением Issues: Read and write на выбранный репозиторий.

Примечание: `.gitignore` уже исключает `node_modules/` и `.env`.

## Запуск
```powershell
npm start
```
Ожидаемый лог: `[MCP] Server started on ws://localhost:3001`

## Протокол MCP (JSON-RPC over WebSocket)
- URL: `ws://<host>:<port>` (по умолчанию `ws://localhost:3001`)
- Общая форма сообщения:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "method/name",
  "params": { /* ... */ }
}
```

## Логирование и диагностика

- Сервер пишет логи в JSON-формате (одна строка = один JSON-объект).
- Ключевые поля:
  - `ts` — ISO‑время
  - `level` — `info` | `warn` | `error`
  - `event` — тип события (`server_started`, `ws_connection_open`, `rpc_request`, `rpc_response`, `rpc_parse_error`, ...)
  - `traceId` — уникальный идентификатор запроса (для корреляции `rpc_request` ↔ `rpc_response`)
  - `id`, `method`, `code`, `error`, `durationMs`, `tool` — контекст запроса/ответа

Примеры логов:
```json
{"ts":"2025-08-21T19:20:00.000Z","level":"info","event":"server_started","port":3001,"url":"ws://localhost:3001"}
{"ts":"2025-08-21T19:20:05.000Z","level":"info","event":"rpc_request","traceId":"...","id":1,"method":"tools/call"}
{"ts":"2025-08-21T19:20:05.100Z","level":"info","event":"rpc_response","traceId":"...","id":1,"method":"tools/call","ok":true,"durationMs":100,"tool":"create_issue"}
```

### Коды ошибок JSON‑RPC
- Базовые (спецификация JSON-RPC 2.0):
  - `-32700` Parse error
  - `-32600` Invalid Request
  - `-32601` Method not found (включая неизвестные инструменты)
  - `-32602` Invalid params
  - `-32603` Internal error

- Серверные (расширенная диагностика):
  - `-32001` Server misconfiguration (например, отсутствует `GITHUB_TOKEN`/`TELEGRAM_BOT_TOKEN`)
  - `-32010` GitHub API error (поля: `status`, `data`, `url`)
  - `-32011` Telegram API error (поля: `status`, `data`, `methodName`)
  - `-32020` Docker error (действия `pull`/`run`/`start`, поля: `action`, `image`/`container_name`, `error`)
  - `-32021` Workspace preparation failed (ошибка подготовки временного каталога/записи файлов)

Каждому запросу соответствует `traceId`, который присутствует в логах запроса и ответа, что позволяет быстро найти связанный стек событий и измерить `durationMs`.

### Методы
- `initialize`
  - Ответ: `{ serverInfo, capabilities }`, где `capabilities.tools = true`
- `tools/list`
  - Ответ: `{ tools: [{ name, description, inputSchema }, ...] }`
- `tools/call`
  - Параметры: `{ name: string, arguments: object }`
  - Ответ: `{ name, result }`

### Инструменты
- `get_repo`
  - Вход: `{ owner: string, repo: string }`
  - Результат: объект репозитория GitHub
- `search_repos`
  - Вход: `{ query: string }`
  - Результат: `items[]` поиска репозиториев
- `create_issue`
  - Вход: `{ owner: string, repo: string, title: string, body?: string }`
  - Результат: созданный issue
- `list_issues`
  - Вход: `{ owner: string, repo: string, state?: string, per_page?: number, page?: number }`
  - Результат: список issues репозитория
- `create_release`
  - Вход: `{ owner: string, repo: string, tag_name: string, name?: string, body?: string, draft?: boolean, prerelease?: boolean, target_commitish?: string }`
  - Результат: объект релиза
- `list_pull_requests`
  - Вход: `{ owner: string, repo: string, state?: string, per_page?: number, page?: number }`
  - Значения по умолчанию: `state = "open"`, `per_page = 10`, `page = 1`
  - Результат: массив PR
- `get_pull_request`
  - Вход: `{ owner: string, repo: string, number: number }`
  - Результат: объект PR
- `list_pr_files`
  - Вход: `{ owner: string, repo: string, number: number, per_page?: number, page?: number }`
  - Значения по умолчанию: `per_page = 100`, `page = 1`
  - Результат: массив файлов PR
- `tg_send_message`
  - Вход: `{ chat_id?: string, text: string, parse_mode?: string, disable_web_page_preview?: boolean }`
  - Результат: отправленное сообщение
- `tg_send_photo`
  - Вход: `{ chat_id?: string, photo: string, caption?: string, parse_mode?: string }`
  - Результат: отправленное фото
- `tg_get_updates`
  - Вход: `{ offset?: number, timeout?: number, allowed_updates?: string[] }`
  - Результат: список обновлений
- `create_issue_and_notify`
  - Вход: `{ owner: string, repo: string, title: string, body?: string, chat_id?: string, message_template?: string }`
  - Результат: созданный issue и отправленное уведомление

- `docker_start_java`
  - Вход: `{ container_name?: string, image?: string, port?: number, extra_args?: string }`
  - Значения по умолчанию: `container_name = "java-dev"`, `image = "eclipse-temurin:20-jdk"`, `port = 8080`, `extra_args = ""`
  - Поведение: если контейнер существует — запускает (если не запущен); если нет — `docker pull` и `docker run -d --restart unless-stopped -p <port>:8080 <image> tail -f /dev/null`
  - Результат: `{ container: string, image: string, state: 'running', existed?: boolean, id?: string }`

Примечание по `docker_exec_java` и JUnit4:
- Сервер автоматически обнаруживает импорты JUnit4 (`import org.junit...`, `@Test`) и подгружает JAR-файлы `junit-4.13.2.jar` и `hamcrest-core-1.3.jar` из Maven Central во временную директорию на хосте, монтируемую в контейнер (`/work/lib`).
- При обнаружении JUnit4 классы компилируются с соответствующим classpath, а запуск производится через `org.junit.runner.JUnitCore <FQCN>`, где `<FQCN>` — полностью квалифицированное имя класса теста (определяется из `package` + имени файла или берётся из аргумента `entrypoint`).
- Если JUnit4 не обнаружен, сервер запускает обычный `main` указанного класса.

### Примеры JSON-RPC
- Инициализация:
```json
{ "jsonrpc": "2.0", "id": 1, "method": "initialize" }
```
- Список инструментов:
```json
{ "jsonrpc": "2.0", "id": 2, "method": "tools/list" }
```
- Вызов инструмента `create_issue`:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "create_issue",
    "arguments": {
      "owner": "Aristman",
      "repo": "AI-intensive",
      "title": "MCP: баг в настройках",
      "body": "Описание проблемы..."
    }
  }
}
```
Ожидаемый ответ:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": { "name": "create_issue", "result": { /* объект issue */ } }
}
```
- Вызов инструмента `list_issues`:
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "list_issues",
    "arguments": {
      "owner": "Aristman",
      "repo": "AI-intensive",
      "state": "open",
      "per_page": 5,
      "page": 1
    }
  }
}
```
Ожидаемый ответ:
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": { "name": "list_issues", "result": [ /* массив issues без PR */ ] }
}
```

- Вызов инструмента `create_release`:
```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "tools/call",
  "params": {
    "name": "create_release",
    "arguments": {
      "owner": "Aristman",
      "repo": "AI-intensive",
      "tag_name": "v1.0.0",
      "name": "Release v1.0.0",
      "body": "Notes...",
      "draft": false,
      "prerelease": false,
      "target_commitish": "main"
    }
  }
}
```
Ожидаемый ответ:
```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "result": { "name": "create_release", "result": { /* объект релиза */ } }
}
```

- Вызов инструмента `list_pull_requests`:
```json
{
  "jsonrpc": "2.0",
  "id": 8,
  "method": "tools/call",
  "params": {
    "name": "list_pull_requests",
    "arguments": {
      "owner": "Aristman",
      "repo": "AI-intensive",
      "state": "open",
      "per_page": 5,
      "page": 1
    }
  }
}
```
Ожидаемый ответ:
```json
{
  "jsonrpc": "2.0",
  "id": 8,
  "result": { "name": "list_pull_requests", "result": [ /* массив PR */ ] }
}
```

- Вызов инструмента `get_pull_request`:
```json
{
  "jsonrpc": "2.0",
  "id": 9,
  "method": "tools/call",
  "params": {
    "name": "get_pull_request",
    "arguments": {
      "owner": "Aristman",
      "repo": "AI-intensive",
      "number": 123
    }
  }
}
```
Ожидаемый ответ:
```json
{
  "jsonrpc": "2.0",
  "id": 9,
  "result": { "name": "get_pull_request", "result": { /* объект PR */ } }
}
```

- Вызов инструмента `list_pr_files`:
```json
{
  "jsonrpc": "2.0",
  "id": 10,
  "method": "tools/call",
  "params": {
    "name": "list_pr_files",
    "arguments": {
      "owner": "Aristman",
      "repo": "AI-intensive",
      "number": 123,
      "per_page": 100,
      "page": 1
    }
  }
}
```
Ожидаемый ответ:
```json
{
  "jsonrpc": "2.0",
  "id": 10,
  "result": { "name": "list_pr_files", "result": [ /* массив файлов PR */ ] }
}
```

- Вызов инструмента `search_repos`:
```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "tools/call",
  "params": {
    "name": "search_repos",
    "arguments": {
      "query": "flutter mcp"
    }
  }
}
```
Ожидаемый ответ:
```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": { "name": "search_repos", "result": { "items": [ /* ... */ ] } }
}
```

- Вызов инструмента `docker_start_java`:
```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "tools/call",
  "params": {
    "name": "docker_start_java",
    "arguments": {
      "container_name": "java-dev",
      "image": "eclipse-temurin:20-jdk",
      "port": 8080
    }
  }
}
```
Ожидаемый ответ:
```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "name": "docker_start_java",
    "result": {
      "container": "java-dev",
      "image": "eclipse-temurin:17-jdk",
      "state": "running",
      "existed": false,
      "id": "<container_id>"
    }
  }
}
```

Альтернатива — ручной запуск через Docker CLI (эквивалентно тому, что делает инструмент):
```bash
docker pull eclipse-temurin:20-jdk
docker run -d --name java-dev --restart unless-stopped -p 8080:8080 eclipse-temurin:20-jdk tail -f /dev/null
docker ps --filter name=^/java-dev$
# перезапуск/остановка при необходимости
docker stop java-dev
docker start java-dev
```

## Использование во Flutter
- Клиент: `sample_app/lib/services/mcp_client.dart`
  - Методы: `connect(url)`, `initialize()`, `toolsList()`, `toolsCall(name, args)`, `close()`
- Настройки/UI: `sample_app/lib/screens/settings_screen.dart`
  - Переключатель: “Использовать внешний MCP сервер”
  - Поле: `MCP WebSocket URL` (например, `ws://localhost:3001`)
  - Кнопка: “Проверить MCP” — подключение и инициализация
  - Блок “Быстрый тест: создать GitHub Issue” отображается, если включён GitHub MCP ИЛИ включён внешний MCP сервер. При активном MCP‑сервере локальный токен не требуется.

### Пример кода (Dart): создание issue через MCP
```dart
Future<void> createIssueViaMcp() async {
  final client = McpClient();
  try {
    await client.connect('ws://localhost:3001');
    await client.initialize();

    final issue = await client.toolsCall('create_issue', {
      'owner': 'Aristman',
      'repo': 'AI-intensive',
      'title': 'Пример issue из Flutter',
      'body': 'Создано через MCP сервер.',
    });

    // В issue может быть html_url/url/номер — выведите нужные поля
    print('Issue created: ${issue['html_url'] ?? issue['url'] ?? issue}');
  } catch (e) {
    print('MCP error: $e');
  } finally {
    await client.close();
  }
}
```

## Безопасность
- `GITHUB_TOKEN` хранится только в `.env` MCP‑сервера и не покидает сервер.
- Клиенты не передают токен по сети — сервер сам авторизует вызовы к GitHub API.

## Промпты (готовые шаблоны)

### Вариант A — системный промпт (для ассистента)
```
Ты подключён к MCP серверу и можешь вызывать инструменты:
- create_issue(owner: string, repo: string, title: string, body?: string)

Правила:
1) Если пользователь просит создать GitHub issue, собери недостающие параметры (owner, repo, title, body).
2) Подтверди с пользователем финальные значения полей.
3) Вызови инструмент tools/call create_issue с полями { owner, repo, title, body }.
4) Верни пользователю номер и ссылку на созданный issue.
Если данных недостаточно — уточни.
```

### Вариант B — пользовательский запрос (что ввести)
```
Создай issue в owner=Aristman, repo=AI-intensive
Заголовок: MCP: баг в настройках
Описание: При включённом MCP сервере блок “Быстрый тест” должен отображаться без включения Github MCP провайдера.
```
Либо с подтверждением:
```
Создай GitHub issue через MCP сервер.
owner: Aristman
repo: AI-intensive
title: MCP: баг в настройках
body: При включённом MCP сервере блок “Быстрый тест” должен отображаться без включения Github MCP провайдера. Добавить условие OR.

Подтверди поля и выполни.
```

### Вариант C — прямой JSON-RPC к MCP серверу
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "create_issue",
    "arguments": {
      "owner": "Aristman",
      "repo": "AI-intensive",
      "title": "MCP: баг в настройках",
      "body": "Описание проблемы..."
    }
  }
}
```

## Отладка и частые ошибки
- `GITHUB_TOKEN is not configured on server` — не заполнен токен в `.env` сервера
- `WebSocket closed`/таймаут — проверьте URL, порт, что сервер запущен
- 401/403 при `create_issue` — у токена нет нужных прав на репозиторий

## Деплой на удалённый сервер
В каталоге `mcp_server/` есть скрипты деплоя, которые копируют нужные файлы на сервер с помощью `ssh/scp`.

- Назначение по умолчанию: `ai-intensive/mcp_server`
- Копируются файлы: `server.js`, `package.json`, `package-lock.json`, `README.md` и все прочие `.js` из каталога (без `node_modules`). Если рядом есть `.env`, он также будет скопирован в каталог назначения.

Linux/macOS:
```bash
./deploy.sh user@your-host             # в ai-intensive/mcp_server
./deploy.sh user@your-host /opt/ai-intensive/mcp_server  # в указанный путь
```

Windows (PowerShell):
```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Server user@your-host
powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Server user@your-host -DestPath /opt/ai-intensive/mcp_server
```

После копирования запустить на сервере:
```bash
ssh user@your-host 'cd ai-intensive/mcp_server && npm install && npm start'
```

Альтернатива: запуск через скрипты с указанием пути к .env
```bash
# Linux/macOS
ssh user@your-host 'cd ai-intensive/mcp_server && ./start.sh'                     # использует ./\.env
ssh user@your-host 'cd ai-intensive/mcp_server && ./start.sh /path/to/.env'      # явный путь
# в фоне (daemon):
ssh user@your-host 'cd ai-intensive/mcp_server && ./start.sh -d'                  # nohup, логи в mcp_server.log, PID в mcp_server.pid

# Windows (PowerShell на сервере Windows)
powershell -ExecutionPolicy Bypass -File .\start.ps1                               # использует .\.env
powershell -ExecutionPolicy Bypass -File .\start.ps1 -EnvPath C:\\path\\to\\.env
# в фоне (daemon):
powershell -ExecutionPolicy Bypass -File .\start.ps1 -Background                  # логи в mcp_server.log, PID в mcp_server.pid
```

### Остановка

```bash
# Linux/macOS
./stop.sh

# Windows PowerShell
powershell -ExecutionPolicy Bypass -File .\stop.ps1
```

### Установка как systemd-сервис (Linux)

Скрипт `install-systemd.sh` создаёт сервис и сразу запускает его.

```bash
ssh user@your-host 'cd ai-intensive/mcp_server && sudo ./install-systemd.sh \
  --name ai-intensive-mcp \
  --user $USER \
  --env /path/to/.env'

# Управление
sudo systemctl status ai-intensive-mcp
sudo systemctl restart ai-intensive-mcp
sudo systemctl stop ai-intensive-mcp
sudo systemctl disable ai-intensive-mcp

# Логи
tail -f ai-intensive/mcp_server/mcp_server.log
```

### Удаление systemd‑сервиса (Linux)

```bash
ssh user@your-host 'cd ai-intensive/mcp_server && sudo ./uninstall-systemd.sh --name ai-intensive-mcp'
```

## Архитектурные заметки
- Сервер — самостоятельный процесс Node.js, не встраивается в приложение.
- Flutter может переключаться между прямыми REST-вызовами и MCP‑сервером.
- MCP‑клиент абстрагирует JSON‑RPC коммуникацию и обработку ошибок.
