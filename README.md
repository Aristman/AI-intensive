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
  - Автоопределяет `entrypoint` (FQCN) и корректный путь `filename` по `package` из исходника.
  - Подробности в `sample_app/README.md`.
  
  Flutter app (CodeOpsAgent + chat UI) integrated with MCP:
  - Runs Java code in Docker via MCP (`docker_exec_java`).
  - Automatically infers Java `entrypoint` (FQCN) and `filename` path from source `package`.
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

- Инструменты MCP с примерами JSON‑RPC описаны в `mcp_server/README.md`.
- CodeOpsAgent умеет сжимать историю чата и вызывать MCP при включённом режиме.
- Инструмент Java/Docker компилирует и запускает код в контейнере с таймаутами и лимитами.

---

## Roadmap / Дорожная карта

See `ROADMAP.md` for current milestones and tasks.

Актуальные планы и задачи смотрите в `ROADMAP.md`.
