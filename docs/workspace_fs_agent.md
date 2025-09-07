# Workspace FS Agent

Агент безопасной работы с файловой системой в пределах корня workspace. Предоставляет инструменты для получения списка файлов и папок, чтения и записи файлов, а также удаления файлов/директорий.

Файлы:
- `sample_app/lib/agents/workspace/file_system_service.dart` — сервис безопасного доступа к ФС (песочница)
- `sample_app/lib/agents/workspace/workspace_fs_agent.dart` — агент (`IToolingAgent`) поверх сервиса
- DTO: `sample_app/lib/agents/workspace/workspace_file_entities.dart`

## Возможности

- Список директории: `fs_list`
- Чтение файла (превью до 64KB): `fs_read`
- Запись файла: `fs_write` (по умолчанию без перезаписи, флаг `overwrite=true` при необходимости)
- Удаление: `fs_delete` (для удаления директорий нужен флаг `recursive=true`)

## Модель безопасности (песочница)

- Все пути нормализуются и проверяются на принадлежность корню `rootDir` (по умолчанию `Directory.current.path`).
- Запрещён выход за пределы корня (path traversal, абсолютные пути вне корня, симлинки по возможности блокируются проверкой `isWithin`).
- При нарушении — человеко‑читаемые сообщения об ошибках.

## Форматы инструментов

### fs_list
Вход:
```
{
  "path": "."  // относительный или абсолютный путь (внутри корня)
}
```
Выход:
```
{
  "ok": true,
  "path": "a/b",
  "entries": [ {"name": "src", "isDir": true}, {"name": "main.dart", "isDir": false, "size": 1234} ],
  "message": "optional"
}
```

### fs_read
Вход:
```
{ "path": "README.md" }
```
Выход:
```
{
  "ok": true,
  "path": "README.md",
  "isDir": false,
  "size": 2048,
  "contentSnippet": "...первые символы...",
  "message": "Файл: README.md\nРазмер: 2048 байт\n..."
}
```

### fs_write
Вход:
```
{
  "path": "docs/plan.md",
  "content": "# План\n...",
  "createDirs": true,
  "overwrite": false
}
```
Выход:
```
{ "ok": true, "path": "docs/plan.md", "bytesWritten": 123, "message": "Записано 123 байт в docs/plan.md" }
```

### fs_delete
Вход:
```
{ "path": "build", "recursive": true }
```
Выход:
```
{ "ok": true, "path": "build", "message": "Удалено: build" }
```

## Примеры использования (Dart)

```dart
final agent = WorkspaceFsAgent(rootDir: projectRoot);

final listRes = await agent.callTool('fs_list', { 'path': '.' });
final readRes = await agent.callTool('fs_read', { 'path': 'README.md' });
final writeRes = await agent.callTool('fs_write', {
  'path': 'notes/todo.txt',
  'content': 'add docs',
  'createDirs': true,
  'overwrite': false,
});
final delRes = await agent.callTool('fs_delete', { 'path': 'notes', 'recursive': true });
```

Для быстрой ручной проверки доступны текстовые команды через `ask()`:
- `list <path>`
- `read <path>`
- `write <path>: <content>`
- `delete [-r] <path>`

## Тесты

- `sample_app/test/file_system_service_test.dart`
- `sample_app/test/workspace_fs_agent_test.dart`

Они покрывают запись/чтение, листинг, удаление (включая рекурсивное), а также запрет выхода за пределы корня.

## Ограничения и заметки

- Превью чтения ограничено 64KB, чтобы не блокировать UI и не расходовать память.
- Для директорий удаление без `recursive=true` возможно только если директория пуста.
- По умолчанию запись не перезаписывает существующий файл: укажите `overwrite=true`, если поведение должно измениться.
