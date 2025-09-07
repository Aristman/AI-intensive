# ROADMAP: FS MCP Server (Python, STDIO) + WorkspaceFsMcpAgent

Цель: реализовать Python MCP сервер (STDIO/STDOUT) для операций с файловой системой (песочница), клиент STDIO в Dart и агента `WorkspaceFsMcpAgent` для интеграции в оркестратор.

## Чек‑лист задач

- [ ] Python MCP сервер (STDIO)
  - [ ] Протокол: `initialize`, `tools/list`, `tools/call`
  - [ ] Инструменты: `fs_list`, `fs_read`, `fs_write`, `fs_delete`
  - [ ] Песочница путей: нормализация, запрет выхода за корень (`FS_ROOT` или CWD)
  - [ ] README с примерами, переменные окружения, запуск

- [ ] Dart STDIO MCP клиент
  - [ ] Процесс запуска `python server.py`, обмен JSON‑RPC через stdin/stdout
  - [ ] Методы: `initialize()`, `toolsList()`, `callTool(name, args)`; кэш инструментов
  - [ ] Обработка ошибок и завершения процесса

- [ ] WorkspaceFsMcpAgent (Dart)
  - [ ] Инструменты: `fs_list`, `fs_read`, `fs_write`, `fs_delete` через STDIO клиент
  - [ ] Совместимость с `IToolingAgent` и `AuthPolicyMixin`

- [ ] Интеграция в оркестратор
  - [ ] Переключатель использования MCP агента (конструктор/флаг `useFsMcp`)
  - [ ] Делегирование файловых команд MCP агенту при включённом флаге, иначе — локальный `FileSystemService`

- [ ] Тесты
  - [ ] Юнит‑тесты Python сервера (локальные функции)
  - [ ] Юнит‑тесты Dart клиента (моки процесса)
  - [ ] Интеграционный тест агента с фейковым STDIO процессом

- [ ] Документация
  - [ ] `mcp_servers/fs_mcp_server_py/README.md`
  - [ ] Ссылки в `README.md` и примеры использования агента

## Нефункциональные требования
- Безопасность путей (path traversal)
- Кроссплатформенность (Windows/Unix)
- Простота запуска (зависимости по минимуму)
