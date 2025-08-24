# AI-intensive Monorepo / Монорепозиторий

This repository contains multiple projects that showcase and integrate AI-assisted development workflows, an MCP (Model Context Protocol) server, a Flutter sample app with a CodeOps agent, and JVM services.

Данный репозиторий содержит несколько проектов для демонстрации и интеграции AI‑помощника в разработке, MCP‑сервера, Flutter‑приложения с агентом CodeOps и JVM‑сервисов.

---

## Repository Structure / Структура репозитория

- `mcp_server/`
  - Node.js MCP server (WebSocket JSON‑RPC) with tools:
    - Repos: `get_repo`, `search_repos`, `create_issue`
    - Docker/Java: `docker_exec_java`
    - Telegram: `tg_send_message`, `tg_send_photo`, `tg_get_updates`
    - Composite: `create_issue_and_notify`
  - See `mcp_server/README.md` for detailed setup and usage.
  
  MCP‑сервер на Node.js (WebSocket JSON‑RPC) с инструментами:
  - Репозитории: `get_repo`, `search_repos`, `create_issue`
  - Docker/Java: `docker_exec_java`
  - Telegram: `tg_send_message`, `tg_send_photo`, `tg_get_updates`
  - Составной: `create_issue_and_notify`
  - Подробности в `mcp_server/README.md`.

- `sample_app/`
  - Flutter приложение (CodeOpsAgent + чат‑интерфейс), интегрированное с MCP.
  - Умеет запускать Java‑код внутри Docker через MCP (`docker_exec_java`).
  - Автоопределяет `entrypoint` (FQCN) и корректный путь `filename` по `package`.
  - Глобальный AppBar (`HomeScreen`) содержит индикатор статуса MCP: `MCP off`/`MCP ready`/`MCP active`; тултип показывает URL MCP или сообщение о fallback.
  - Навигация построена на enum `Screen` как едином источнике правды (иконки, лейблы, пункты нижней навигации и фабрика страниц) — см. `sample_app/lib/screens/screens.dart`.
  - Подробности в `sample_app/README.md`.
  
  Flutter app (CodeOpsAgent + chat UI) integrated with MCP:
  - Runs Java code in Docker via MCP (`docker_exec_java`).
  - Automatically infers Java `entrypoint` (FQCN) and `filename` path from source `package`.
  - Global AppBar (`HomeScreen`) contains an MCP status chip: `MCP off`/`MCP ready`/`MCP active`; tooltip shows MCP URL or fallback note.
  - Navigation is driven by the `Screen` enum as the single source of truth (icons, labels, bottom navigation destinations, and page factory) — see `sample_app/lib/screens/screens.dart`.
  - See `sample_app/README.md` for details.

- `issue-monitor/`
  - JVM/Gradle subproject (Kotlin), auxiliary service for repository issue workflows.
  - См. `issue-monitor/README.md`.

- Root Gradle JVM module (this directory)
  - Kotlin/JVM build with minimal scaffolding (`src/`, `build.gradle.kts`).
  - Базовый модуль Kotlin/JVM (минимальная заготовка).

- Other files / Прочее:
  - `ROADMAP.md` — project plan and upcoming tasks / план работ
  - `gradle/`, `gradlew`, `gradlew.bat`, `gradle.properties` — Gradle wrapper

---

## Prerequisites / Предпосылки

- Docker Desktop / Docker Engine
- Node.js LTS (for `mcp_server/`)
- Flutter SDK + Dart (for `sample_app/`)
- JDK 17+ and Gradle (for JVM modules)

---

## Quick Start / Быстрый старт

1) Start MCP server / Запустите MCP‑сервер
- See `mcp_server/README.md` for `.env` and run instructions.
- Подробности в `mcp_server/README.md` (настройка `.env`, запуск).

2) Run the Flutter sample app / Запустите пример Flutter
- `cd sample_app` then `flutter run`
- Enable MCP in settings (URL: `ws://localhost:3001`).
- Включите MCP в настройках (URL: `ws://localhost:3001`).

3) Execute Java via Docker / Выполнение Java в Docker
- In CodeOps chat, paste or generate Java code and confirm run.
- Клиент автоматически подставит FQCN в `entrypoint` и путь файла по `package`.

4) Tests / Тесты
- Flutter: `cd sample_app && flutter test`
- JVM modules: `./gradlew test`

---

## Development Notes / Заметки разработки

- MCP tools are documented with JSON‑RPC examples in `mcp_server/README.md`.
- CodeOpsAgent compresses chat history and integrates MCP calls when enabled.
- The Java Docker tool compiles and runs code inside container with timeouts and resource limits.
- Централизованный резолвер LLM: `sample_app/lib/domain/llm_resolver.dart`; все агенты используют общий `resolveLlmUseCase(AppSettings)` вместо приватных дубликатов.
- Новый оркестратор `CodeOpsBuilderAgent` реализует унифицированный интерфейс `IAgent`/`IToolingAgent` и композиционно использует `CodeOpsAgent`.
  На запросы пользователя генерирует классы, спрашивает про создание тестов, запускает JUnit4‑тесты в Docker через MCP, анализирует результаты и при необходимости пытается доработать тесты. См. `sample_app/lib/agents/code_ops_builder_agent.dart`.
- Поддерживается стриминг событий пайплайна в UI (прогресс, live‑лог, подтверждения). Подробнее: `docs/code_ops_builder_agent.md`.
  - `pipeline_complete` теперь эмитится только после этапа тестов (успех/падение) либо при явном отказе от тестов; после генерации кода пайплайн переходит в `ask_create_tests`.
  - Мульти‑ходовое продолжение: если исходный запрос без языка, `start()` принимает короткий ответ‑уточнение (например, «Java») и продолжает генерацию, используя сохранённый промпт.
  - Двухфазные подтверждения: событие `ask_create_tests` эмитится дважды с `meta.action = 'create_tests'` и `meta.action = 'run_tests'`; подтверждения отправляются через повторный потоковый вызов `start()`.
  - События `test_generated` содержат `meta.language` и список `meta.tests` вида `{ path, content }` для UI.
  - Нормализация ключей результатов тестов: агент принимает как `exit_code`, так и `exitCode` (а также `stdout`/`stderr`) из MCP и корректно определяет статус прогона.
  - Новые события запуска тестов: `docker_exec_started` (пакетный старт) и `docker_exec_result` (по одному на тест, включая повтор после рефайна). Во всех событиях присутствует `runId` для корреляции.
  - Fallback‑поведение: если MCP выключен или `mcpServerUrl` не задан, `CodeOpsBuilderAgent` делегирует запуск Java во внутренний `CodeOpsAgent` (для тестов/моков). При включённом MCP используется локальный MCP‑клиент.
- Планируется кнопка отмены пайплайна в UI и поддержка отмены в агенте (см. `ROADMAP.md`).
- Оркестратор хранит и управляет контекстом беседы и состоянием пайплайна (runId, intent, language, entrypoint, files, статус).
- Тестовые файлы исключаются из основного результата генерации кода; тесты создаются и запускаются отдельно.
- Все события стриминга содержат `runId` для корреляции с конкретным запуском.
 пайплайна.

- Совместимость с YandexGPT: для повышения соблюдения строгого JSON в `sample_app/lib/data/llm/yandexgpt_usecase.dart` системные инструкции переносятся в первое `user`‑сообщение. В `sample_app/lib/agents/code_ops_builder_agent.dart` добавлен fallback при отсутствии JSON — извлечение кода и тестов из fenced‑блоков и формирование минимального валидного JSON для продолжения пайплайна. Покрыто тестами: `sample_app/test/code_ops_builder_agent_yandex_fallback_test.dart`. Подробности: раздел «Совместимость с YandexGPT» в `docs/code_ops_builder_agent.md`.

---

## Roadmap / Дорожная карта

See `ROADMAP.md` for current milestones and tasks.

Актуальные планы и задачи смотрите в `ROADMAP.md`.
