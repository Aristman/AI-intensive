import 'dart:io';

/// Простая реализация применения патчей с возможностью отката последней операции.
/// Поддерживаемые форматы патча:
/// - { 'path': String, 'newContent': String }
/// - { 'path': String, 'diff': String } — только для простых unified diff по всему файлу
class PatchApplyService {
  Map<String, _BackupEntry>? _lastBackup; // path -> backup

  bool get canRollback => _lastBackup != null && _lastBackup!.isNotEmpty;

  /// Применяет патчи. Если указан `newContent` — записывает его.
  /// Если указан только `diff` — пытается извлечь новое содержимое из
  /// простого unified diff (один хунк по всему файлу, без контекстных строк).
  /// Возвращает количество применённых файлов.
  Future<int> applyPatches(List<Map<String, dynamic>> patches) async {
    if (patches.isEmpty) return 0;
    // Сформируем бэкапы
    final backup = <String, _BackupEntry>{};
    var applied = 0;

    try {
      for (final p in patches) {
        final path = p['path'] as String?;
        if (path == null) continue;
        String? newContent = p['newContent'] as String?;
        if (newContent == null && p['diff'] is String) {
          newContent = _tryExtractNewContentFromFullFileUnifiedDiff(p['diff'] as String);
          if (newContent == null) {
            // Неподдерживаемый diff — пропускаем без ошибки (безопасное поведение)
            continue;
          }
        }
        if (newContent == null) continue;

        final file = File(path);
        final existed = await file.exists();
        final original = existed ? await file.readAsString() : '';

        // сохраним бэкап в памяти и на диск (.bak)
        final bakPath = '$path.bak';
        await File(bakPath).writeAsString(original);
        backup[path] = _BackupEntry(bakPath: bakPath, originalContent: original);

        // применим новое содержимое
        await file.create(recursive: true);
        await file.writeAsString(newContent);
        applied++;
      }

      // успешно — фиксируем бэкап как последний
      _lastBackup = backup;
      return applied;
    } catch (e) {
      // попытка восстановить уже изменённые файлы
      if (backup.isNotEmpty) {
        for (final entry in backup.entries) {
          final path = entry.key;
          final original = entry.value.originalContent;
          try {
            await File(path).writeAsString(original);
          } catch (_) {}
        }
      }
      rethrow;
    }
  }

  /// Откатывает последнюю операцию applyPatches.
  /// Возвращает количество восстановленных файлов.
  Future<int> rollbackLast() async {
    final backup = _lastBackup;
    if (backup == null || backup.isEmpty) return 0;
    var restored = 0;
    for (final entry in backup.entries) {
      final path = entry.key;
      final original = entry.value.originalContent;
      try {
        await File(path).writeAsString(original);
        restored++;
      } catch (_) {}
      // удалим .bak
      try {
        final bakPath = entry.value.bakPath;
        if (bakPath != null) {
          final bak = File(bakPath);
          if (await bak.exists()) {
            await bak.delete();
          }
        }
      } catch (_) {}
    }
    _lastBackup = null;
    return restored;
  }
}

class _BackupEntry {
  final String? bakPath;
  final String originalContent;
  _BackupEntry({required this.bakPath, required this.originalContent});
}

/// Возвращает новое содержимое файла из простого unified diff, если удаётся.
/// Условия:
/// - присутствуют заголовки `--- a/` и `+++ b/`
/// - один хунк `@@ -1,OLD +1,NEW @@`
/// - строки гана состоят только из `-` и `+` (без пробельных/контекстных ` `)
/// В этом случае новое содержимое формируется из всех `+` строк (без лидирующего '+'),
/// соединённых через `\n`.
String? _tryExtractNewContentFromFullFileUnifiedDiff(String diff) {
  final lines = diff.split('\n');
  if (lines.length < 4) return null;
  if (!lines[0].startsWith('--- a/')) return null;
  if (!lines[1].startsWith('+++ b/')) return null;
  if (!lines[2].startsWith('@@ -1,')) return null;
  if (!lines[2].contains(' +1,')) return null;

  // Проверим, что дальше нет контекстных строк
  final body = lines.sublist(3);
  for (final l in body) {
    if (l.isEmpty) continue; // пустые строки допустимы (последняя пустая при завершающем \n)
    final ch = l[0];
    if (ch != '-' && ch != '+') {
      return null; // контекстные строки/нестандартный diff
    }
  }

  final out = <String>[];
  for (final l in body) {
    if (l.startsWith('+')) {
      out.add(l.substring(1));
    }
  }
  var s = out.join('\n');
  if (s.isNotEmpty && !s.endsWith('\n')) {
    s = '$s\n';
  }
  return s;
}
