import 'dart:io';

/// Простая реализация применения патчей с возможностью отката последней операции.
/// Патч ожидается в формате карты: { 'path': String, 'newContent': String }
class PatchApplyService {
  Map<String, _BackupEntry>? _lastBackup; // path -> backup

  bool get canRollback => _lastBackup != null && _lastBackup!.isNotEmpty;

  /// Применяет патчи (перезаписывает файлы newContent).
  /// Возвращает количество применённых файлов.
  Future<int> applyPatches(List<Map<String, dynamic>> patches) async {
    if (patches.isEmpty) return 0;
    // Сформируем бэкапы
    final backup = <String, _BackupEntry>{};
    var applied = 0;

    try {
      for (final p in patches) {
        final path = p['path'] as String?;
        final newContent = p['newContent'] as String?;
        if (path == null || newContent == null) continue;

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
