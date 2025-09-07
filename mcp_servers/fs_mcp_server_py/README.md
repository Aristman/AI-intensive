# FS MCP Server (Python, STDIO)

Минимальный MCP сервер для работы с файловой системой. Транспорт — STDIN/STDOUT, JSON‑RPC подобные сообщения по одной строке.

Поддерживаемые методы:
- `initialize`
- `tools/list`
- `tools/call` (инструменты: `fs_list`, `fs_read`, `fs_write`, `fs_delete`)

Песочница:
- Корень песочницы: переменная окружения `FS_ROOT` или текущая директория процесса (CWD).
- Защита от выхода за пределы корня (path traversal).

## Запуск

```bash
# Windows
set FS_ROOT=%CD%
python server.py

# Linux/Mac
export FS_ROOT=$PWD
python3 server.py
```

## Протокол
- Каждое сообщение — одна JSON‑строка (UTF‑8) без разделителей.
- Запрос:
```json
{"jsonrpc": "2.0", "id": 1, "method": "initialize"}
```
- Ответ:
```json
{"jsonrpc": "2.0", "id": 1, "result": {"ok": true, "server": "fs_mcp_server_py", "version": "0.1.0", "fs_root": "..."}}
```

### tools/list
```json
{"jsonrpc": "2.0", "id": 2, "method": "tools/list"}
```
Ответ содержит массив `tools` с описаниями.

### tools/call
```json
{"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "fs_list", "arguments": {"path": "."}}}
```
Ответ:
```json
{"jsonrpc": "2.0", "id": 3, "result": {"ok": true, "result": {"ok": true, "path": ".", "entries": [{"name":"src","isDir":true}]}}}
```

## Инструменты
- `fs_list({ path })` → `{ ok, path, entries:[{name,isDir,size?}], message? }`
- `fs_read({ path })` → `{ ok, path, size, contentSnippet, message }`
- `fs_write({ path, content, createDirs=false, overwrite=false })` → `{ ok, path, bytesWritten, message? }`
- `fs_delete({ path, recursive=false })` → `{ ok, path, message }`

## Зависимости
- Python 3.8+
- Стандартная библиотека (доп. пакеты не требуются)

## Отладка
- Логи выводятся в stderr в JSON‑виде.
