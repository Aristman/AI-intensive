import 'dart:io';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/agents/auto_fix/diff_apply_agent.dart';

/// Простая реализация применения патчей с возможностью отката последней операции.
/// Поддерживаемые форматы патча:
/// - { 'path': String, 'newContent': String }
/// - { 'path': String, 'diff': String } — только для простых unified diff по всему файлу
class PatchApplyService {
  Map<String, _BackupEntry>? _lastBackup; // path -> backup

  bool get canRollback => _lastBackup != null && _lastBackup!.isNotEmpty;

  /// Применяет патчи. Если указан `newContent` — записывает его.
  /// Если указан только `diff` — применяет его через LLM-агента (DiffApplyAgent).
  /// Возвращает количество применённых файлов.
  Future<int> applyPatches(
    List<Map<String, dynamic>> patches, {
    AppSettings? settings,
  }) async {
    if (patches.isEmpty) return 0;
    // Сформируем бэкапы
    final backup = <String, _BackupEntry>{};
    var applied = 0;

    try {
      for (final p in patches) {
        final path = p['path'] as String?;
        if (path == null) {
          continue;
        }
        String? newContent = p['newContent'] as String?;
        final diff = p['diff'] as String?;
        if (newContent == null && diff == null) {}
        if (newContent == null && diff is String) {
          // Сначала пробуем простой парсер полного unified diff (по всему файлу)
          final file = File(path);
          final existed = await file.exists();
          final original = existed ? await file.readAsString() : '';
          final simple = _tryApplySimpleFullFileUnifiedDiff(original, diff);
          if (simple != null) {
            newContent = simple;
          } else if (settings != null) {
            // Если простой парсер не сработал — пробуем LLM-агента (как раньше)
            try {
              final agent = DiffApplyAgent();
              final llmResult = await agent.apply(
                  original: original, diff: diff, settings: settings);
              if (llmResult != null) {
                newContent = llmResult;
              }
            } catch (e) {
              // Intentionally ignored: if LLM-based diff application fails,
              // we leave `newContent` as null so the patch is skipped.
            }
          }
        }
        if (newContent == null) continue;

        final file = File(path);
        final existed = await file.exists();
        final original = existed ? await file.readAsString() : '';

        // сохраним бэкап в памяти и на диск (.bak)
        final bakPath = '$path.bak';
        await File(bakPath).writeAsString(original);
        backup[path] =
            _BackupEntry(bakPath: bakPath, originalContent: original);

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
          } catch (_) {
            // Best-effort restore. Ignore failures during rollback on error.
          }
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
      } catch (_) {
        // Best-effort restore for rollback; ignore individual file failures.
      }
      // удалим .bak
      try {
        final bakPath = entry.value.bakPath;
        if (bakPath != null) {
          final bak = File(bakPath);
          if (await bak.exists()) {
            await bak.delete();
          }
        }
      } catch (_) {
        // Best-effort cleanup of .bak file; safe to ignore.
      }
    }
    _lastBackup = null;
    return restored;
  }

  /// Простой парсер полного unified diff по всему файлу.
  /// Возвращает новое содержимое файла или null, если формат не распознан.
  /// Поддерживаемый формат (один hunk, только замены без контекстных строк):
  /// --- a/...
  /// +++ b/...
  /// @@ -X,Y +U,V @@
  /// -old
  /// +new
  String? _tryApplySimpleFullFileUnifiedDiff(String original, String diff) {
    final lines = diff.split('\n');
    if (lines.length < 4) return null;
    // Проверка заголовков
    if (!lines[0].startsWith('--- a/') || !lines[1].startsWith('+++ b/')) return null;
    // Минимум один hunk
    final hasHunk = lines.any((l) => l.startsWith('@@'));
    if (!hasHunk) return null;

    final plus = <String>[];
    var insideHunk = false;
    for (final l in lines.skip(2)) {
      if (l.startsWith('@@')) {
        insideHunk = true;
        continue;
      }
      if (!insideHunk) continue; // пропускаем всё до первого @@
      if (l.isEmpty) continue;
      if (l.startsWith(' ')) {
        // контекстные строки — не поддерживаем в простом парсере
        return null;
      }
      if (l.startsWith('+++') || l.startsWith('---')) {
        // вторые заголовки — считаем сложным кейсом
        return null;
      }
      if (l.startsWith('+')) {
        // Исключаем заголовок +++
        if (l.startsWith('+++')) return null;
        plus.add(l.substring(1));
      } else if (l.startsWith('-')) {
        // удаляемые строки — игнорируем, результат строим из плюсов
        continue;
      } else {
        // что-то иное — не поддерживаем
        return null;
      }
    }
    if (plus.isEmpty) return null;
    // Собираем новое содержимое, добавляем завершающую новую строку
    final content = plus.join('\n');
    return content.endsWith('\n') ? content : '$content\n';
  }
}

class _BackupEntry {
  final String? bakPath;
  final String originalContent;

  _BackupEntry({required this.bakPath, required this.originalContent});
}
