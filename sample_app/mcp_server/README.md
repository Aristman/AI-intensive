# MCP GitHub Server

Лёгкий MCP-сервер (WebSocket + JSON-RPC 2.0), предоставляющий инструменты GitHub: `get_repo`, `search_repos`, `create_issue`. Используется Flutter-приложением как внешний провайдер данных/действий.

## Возможности
- Инструменты MCP:
  - `get_repo(owner, repo)` — получить информацию о репозитории GitHub
  - `search_repos(query)` — поиск репозиториев GitHub
  - `create_issue(owner, repo, title, body?)` — создать GitHub Issue
- WebSocket JSON-RPC 2.0 интерфейс: методы `initialize`, `tools/list`, `tools/call`
- Токен GitHub хранится только на сервере (безопасно)

## Требования
- Node.js (LTS), npm

## Установка
```powershell
# из каталога sample_app/mcp_server
npm install
```

## Конфигурация окружения (.env)
Создайте файл `.env` из шаблона `.env.example` и заполните значения:
```env
GITHUB_TOKEN=ghp_xxx   # персональный токен, достаточные права для создания issues
PORT=3001              # порт WebSocket сервера (по умолчанию 3001)
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

### Дополнительные примеры JSON-RPC

- Вызов инструмента `get_repo`:
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "get_repo",
    "arguments": {
      "owner": "Aristman",
      "repo": "AI-intensive"
    }
  }
}
```
Ожидаемый ответ:
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": { "name": "get_repo", "result": { /* объект репозитория */ } }
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

## Архитектурные заметки
- Сервер — самостоятельный процесс Node.js, не встраивается в приложение.
- Flutter может переключаться между прямыми REST-вызовами и MCP‑сервером.
- MCP‑клиент абстрагирует JSON‑RPC коммуникацию и обработку ошибок.
