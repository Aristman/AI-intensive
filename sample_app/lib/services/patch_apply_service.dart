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
          // Всегда используем LLM-агента для применения диффа
          final file = File(path);
          final existed = await file.exists();
          final original = existed ? await file.readAsString() : '';
          if (settings == null) {
          } else {
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
}

class _BackupEntry {
  final String? bakPath;
  final String originalContent;

  _BackupEntry({required this.bakPath, required this.originalContent});
}
