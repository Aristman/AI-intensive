# План реализации экрана GitHub‑агента (Reasoning + MCP)

Обновлено: 2025-08-24 23:40 (+03)

## 1) Цели и охват
- Создать экран для работы с GitHub через рассуждающего агента и MCP.
- Контекст репозитория (owner/repo) задаётся через настройки приложения (`AppSettings`), а не полями ввода на экране. На экране доступен локальный диалог настроек для быстрой правки owner/repo и лимитов списков.
- Поле ввода пользовательского запроса активно всегда; при вызове MCP недостающие параметры owner/repo берутся из настроек.
- Агент должен уметь: просматривать репозитории, создавать issues, создавать релизы, проводить код‑ревью PR и создавать issues по результатам.

## 2) Высокоуровневая архитектура
- UI: экран `GitHubAgentScreen` с чат‑полем, отображением текущего контекста `owner/repo` в шапке (`github_repo_context_label`) и кнопкой локальных настроек (`github_local_settings_btn`). Полей ввода owner/repo в основном UI нет.
- Agent: используем существующий `ReasoningAgent` с `extraSystemPrompt`, в котором явно укажем owner/repo и доступные MCP‑инструменты.
- MCP: взаимодействие через `McpClient` и/или сервис‑обёртку. Расширим сервер инструментами для релизов и PR.
- Настройки: читаем `AppSettings` через `SettingsService`, учитываем `useMcpServer` и `mcpServerUrl`.
  - Локальный диалог настроек (в рамках `GitHubAgentScreen`): поля `owner`, `repo`, а также лимиты списков: `githubReposListLimit`, `githubIssuesListLimit`, `githubOtherListLimit`. Поля валидируются (положительные int), сохраняются через `SettingsService` и синхронизируются с контроллерами для переинициализации агента.

## 3) Изменения в Flutter (sample_app)

### 3.1 Экран и навигация
- Файл: `sample_app/lib/screens/github_agent_screen.dart`
  - Поля ввода owner/repo удалены. В шапке отображается текущий контекст с ключом `github_repo_context_label`.
  - Кнопка локальных настроек в шапке с ключом `github_local_settings_btn` открывает диалог (ключи полей: `github_local_owner_field`, `github_local_repo_field`, `github_local_repos_limit_field`, `github_local_issues_limit_field`, `github_local_other_limit_field`; кнопка сохранить: `github_local_save_btn`).
  - Поле запроса (`github_query_field`) и кнопка отправки (`github_send_btn`) остаются без изменений.
  - Инициализация `ReasoningAgent` с `extraSystemPrompt`, содержащим owner/repo из настроек и правила вызова MCP.
  
- Регистрация экрана в меню:
  - Файл: `sample_app/lib/screens/screens.dart`
    - Добавить пункт в enum `Screen` (например, `github` с иконкой `Icons.github` или подходящей).
    - В `screenFactories` добавить фабрику: `Screen.github: (v) => GitHubAgentScreen(key: ValueKey('gh-$v'))`.

### 3.2 Интеграция агента
- Используем `ReasoningAgent` (уже поддерживает `extraSystemPrompt`).
- Формируем `extraSystemPrompt`:
  - Жёстко указываем текущий репозиторий: `owner=<owner>, repo=<repo>`.
  - Описываем доступные MCP‑инструменты и правила их вызова (см. раздел 4).
  - Просим агента уточнять недостающие параметры и соблюдать политику неопределённости (уже есть в `ReasoningAgent`).
- Перед каждым запросом пользователя обновляем `extraSystemPrompt` текущими полями owner/repo.

### 3.3 Сервисный слой для GitHub через MCP
- Вариант A (быстрый старт): вызывать MCP прямо из `McpIntegrationService`/агента; для экрана — не требуются новые методы.
- Вариант B (рекомендуется): создать обёртку `GithubMcpClient`:
  - Файл: `sample_app/lib/services/github_mcp_client.dart`
  - Методы: `createIssue`, `createRelease`, `listPullRequests`, `getPullRequest`, `listPrFiles` (см. §4.2 инструменты сервера).
  - Внутри — вызовы `McpClient.toolsCall()`.
- Приоритет: начать с Варианта A, затем выделить в Вариант B, чтобы упростить тестирование и повторное использование.

### 3.4 Тесты (Flutter)
- Виджет‑тесты `github_agent_screen_local_settings_test.dart`:
  - Открытие локального диалога, валидация и сохранение owner/repo и лимитов.
  - Обновление лейбла контекста в шапке и сохранение настроек (персистентность между ребилдами).
  - Использование owner/repo из настроек, если они не переданы в аргументах MCP инструмента.
  - Применение лимитов списков при суммаризации результатов (`_summarizeToolResult`).
- Существующие тесты `github_agent_screen_mcp_tools_test.dart` продолжают покрывать мост MCP (tools/list, tools/call, форматирование `create_release`, обработку ошибок `-32601`).
- Юнит‑тесты `ReasoningAgent`: проверка, что `extraSystemPrompt` содержит owner/repo и подсказки по MCP (опционально).

## 4) Изменения в MCP сервере (mcp_server)

### 4.1 Существующие инструменты (уже есть)
- `get_repo(owner, repo)` — инфо о репозитории.
- `search_repos(query)` — поиск репозиториев.
- `create_issue(owner, repo, title, body?)` — создание issue.

### 4.2 Новые инструменты (добавить)
- `create_release(owner, repo, tag_name, name?, body?, draft?, prerelease?)`
  - GitHub API: POST `/repos/{owner}/{repo}/releases`
  - Результат: объект релиза (номер, html_url, tag_name, и т.д.).
- `list_pull_requests(owner, repo, state?, per_page?, page?)`
  - GitHub API: GET `/repos/{owner}/{repo}/pulls`
  - По умолчанию: `state=open`, `per_page=10`, `page=1`.
- `get_pull_request(owner, repo, number)`
  - GitHub API: GET `/repos/{owner}/{repo}/pulls/{number}`
- `list_pr_files(owner, repo, number, per_page?, page?)`
  - GitHub API: GET `/repos/{owner}/{repo}/pulls/{number}/files`

Опционально (позже):
- `review_pr_and_create_issues(owner, repo, number, instructions?)`
  - Составной инструмент: получает diff файлов PR, формирует список замечаний и создаёт issues с ссылками на строки/файлы.
  - На первом этапе можно оставить это на совести агента: он вызывает `list_pr_files`, анализирует и затем `create_issue`.

### 4.3 Тесты (Node)
- Добавить unit‑тесты для новых инструментов в `mcp_server/test/server.test.js` (мокаем GitHub API или используем токен тестового репозитория).
- Обновить `mcp_server/README.md` — описать новые инструменты и примеры JSON‑RPC.

### 4.4 JSON‑RPC протокол (мост MCP) — примеры

Ниже приведены эталонные примеры обмена по WebSocket JSON‑RPC между клиентом и MCP‑сервером:

1) initialize
```
{ "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": { "client": "sample_app", "version": "1.0.0" } }
<=
{ "jsonrpc": "2.0", "id": 1, "result": { "server": "mcp_server", "version": "1.0.0" } }
```

2) tools/list
```
{ "jsonrpc": "2.0", "id": 2, "method": "tools/list" }
<=
{ "jsonrpc": "2.0", "id": 2, "result": { "tools": [
  { "name": "get_repo" },
  { "name": "search_repos" },
  { "name": "create_issue" },
  { "name": "create_release" },
  { "name": "list_pull_requests" },
  { "name": "get_pull_request" },
  { "name": "list_pr_files" }
] } }
```

3) tools/call (пример: create_release)
```
{ "jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {
  "name": "create_release",
  "arguments": { "owner": "octocat", "repo": "hello-world", "tag_name": "v1.2.0", "name": "1.2.0", "draft": false, "prerelease": false }
} }
<=
{ "jsonrpc": "2.0", "id": 3, "result": {
  "ok": true,
  "data": { "id": 123, "tag_name": "v1.2.0", "html_url": "https://github.com/octocat/hello-world/releases/tag/v1.2.0", "draft": false, "prerelease": false }
} }
```

Ошибки инструментов:
```
{ "jsonrpc": "2.0", "id": 4, "error": { "code": -32601, "message": "Tool not found" } }
```

## 5) Промпт для ReasoningAgent (черновик)

Пример дополнений к системным инструкциям агента, формируемых динамически:
```
Ты работаешь с GitHub репозиторием owner="<OWNER>", repo="<REPO>" через MCP сервер.
Доступные MCP инструменты и их назначение:
- get_repo(owner, repo): получить информацию о репозитории
- search_repos(query): поиск репозиториев
- create_issue(owner, repo, title, body?): создать issue
- create_release(owner, repo, tag_name, name?, body?, draft?, prerelease?): создать релиз
- list_pull_requests(owner, repo, state?, per_page?, page?): список PR
- get_pull_request(owner, repo, number): получить PR
- list_pr_files(owner, repo, number, per_page?, page?): файлы PR

Правила:
1) Если пользовательская задача требует действий в GitHub — собери недостающие параметры (owner, repo, title, body, tag_name, number и т.п.).
2) Подтверди финальные значения (если есть неопределённость > 0.1 — задай уточнения, но не завершай ответ).
3) Вызови соответствующий MCP инструмент через `tools/call`.
4) Отдай пользователю краткий итог с ссылками (issue url, release url, PR url).
5) Для code‑review PR: получи список файлов PR, опиши замечания и создай issues по найденным проблемам.
```

## 6) План работ по шагам

1. Создать экран `GitHubAgentScreen` (UI, состояние, интеграция `ReasoningAgent`).
2. Зарегистрировать экран в `screens.dart` и проверить навигацию в `HomeScreen`.
3. Минимальный функционал: отправка запроса → ответ агента (без новых MCP инструментов).
4. Расширить MCP сервер новыми инструментами (release, PR): реализация, тесты, README.
5. Добавить клиентские обёртки (`GithubMcpClient`) и интеграцию с экраном/агентом.
6. Виджет‑тесты экрана и юнит‑тесты промпта/клиента.
7. Обновить документацию: `docs/`, `sample_app/README.md`, корневой `README.md`, `ROADMAP.md`.
8. E2E‑проверка: 
   - Просмотр репозитория
   - Создание issue
   - Создание релиза
   - Code review PR с созданием issues

## 7) Критерии приёмки
- Экран отображается в нижней навигации, открывается без ошибок.
- Поле запроса активно всегда; MCP‑вызовы используют owner/repo из настроек (без UI‑полей).
- Агент отвечает и, при включённом MCP, умеет вызывать инструменты для GitHub задач.
- Создание issue и релиза подтверждается ссылками из ответа.
- Code review PR приводит к созданию хотя бы одного issue (для PR с очевидными проблемами).
- Все тесты (Flutter и MCP server) проходят.

## 8) Риски и допущения
- Требуется валидный GitHub токен на MCP сервере с правами на репозиторий.
- Для code review качество зависит от LLM и доступного контекста diff/файлов.
- Сетевые таймауты MCP — нужны разумные значения и ретраи (клиент уже таймаутит по умолчанию).

## 9) Изменяемые файлы (ориентировочно)
- `sample_app/lib/screens/github_agent_screen.dart` (новый)
- `sample_app/lib/screens/screens.dart` (регистрация экрана)
- `sample_app/lib/services/github_mcp_client.dart` (новый; опционально)
- `sample_app/test/github_agent_screen_test.dart` (новый)
- `sample_app/test/reasoning_agent_prompt_test.dart` (новый)
- `mcp_server/server.js` (расширение инструментов)
- `mcp_server/test/server.test.js` (тесты инструментов)
- `mcp_server/README.md` (документация инструментов)
- `docs/github_agent_screen.md` (итоговая документация экрана; создать после реализации)
- `ROADMAP.md`, `README.md` (обновления статуса и ссылок)

## 10) Тайминг (оценка)
- Экран + навигация + базовая интеграция: 0.5–1 день
- Серверные инструменты + тесты: 0.5–1 день
- Клиентские обёртки + тесты: 0.5 дня
- E2E проверка и доки: 0.5 дня

— Конец плана —
