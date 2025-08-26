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
  /// Если указан только `diff` — пытается извлечь новое содержимое из
  /// простого unified diff (один хунк по всему файлу, без контекстных строк).
  /// Возвращает количество применённых файлов.
  Future<int> applyPatches(
    List<Map<String, dynamic>> patches, {
    AppSettings? settings,
    bool allowLlmFallback = true,
    bool forceLlm = false,
  }) async {
    if (patches.isEmpty) return 0;
    // Сформируем бэкапы
    final backup = <String, _BackupEntry>{};
    var applied = 0;
    print('[PatchApplyService] start apply: patches=${patches.length}');

    try {
      for (final p in patches) {
        final path = p['path'] as String?;
        if (path == null) {
          print('[PatchApplyService] skip: path is null, meta=$p');
          continue;
        }
        print('[PatchApplyService] handle path=$path');
        String? newContent = p['newContent'] as String?;
        final diff = p['diff'] as String?;
        if (newContent != null) {
          print('[PatchApplyService] newContent provided directly, length=${newContent.length}');
        } else if (diff != null) {
          final head = diff.split('\n').take(3).join(' | ');
          print('[PatchApplyService] diff provided, length=${diff.length}, head="$head"');
        } else {
          print('[PatchApplyService] skip: neither newContent nor diff provided');
        }
        if (newContent == null && diff is String) {
          // Сначала пробуем простой full-file extractor
          final file = File(path);
          final existed = await file.exists();
          final original = existed ? await file.readAsString() : '';

          if (forceLlm) {
            if (settings == null) {
              print('[PatchApplyService] forceLlm=true but settings=null, cannot use LLM, skipping');
            } else {
              print('[PatchApplyService] forceLlm=true -> using LLM agent for path=$path');
              try {
                final agent = DiffApplyAgent();
                final llmResult = await agent.apply(original: original, diff: diff, settings: settings);
                if (llmResult != null) {
                  newContent = llmResult;
                  print('[PatchApplyService] LLM (forced) produced content, length=${newContent!.length}');
                } else {
                  print('[PatchApplyService] LLM (forced) returned null content');
                }
              } catch (e) {
                print('[PatchApplyService] LLM (forced) error: $e');
              }
            }
          } else {
            newContent = _tryExtractNewContentFromFullFileUnifiedDiff(diff);
            if (newContent == null) {
              // Пробуем применить общий unified diff к оригинальному содержимому
              final applied = _applyUnifiedDiffToContent(original, diff);
              newContent = applied;
              if (newContent == null) {
                print('[PatchApplyService] unified diff apply failed for path=$path');
              } else {
                print('[PatchApplyService] unified diff applied in-memory for path=$path, newLength=${newContent.length}');
              }
              // LLM-фолбэк, если контентное применение не удалось
              if (newContent == null && allowLlmFallback && settings != null) {
                print('[PatchApplyService] trying LLM fallback for path=$path');
                try {
                  final agent = DiffApplyAgent();
                  final llmResult = await agent.apply(original: original, diff: diff, settings: settings);
                  if (llmResult != null) {
                    newContent = llmResult;
                    print('[PatchApplyService] LLM fallback produced content, length=${newContent!.length}');
                  } else {
                    print('[PatchApplyService] LLM fallback returned null content');
                  }
                } catch (e) {
                  print('[PatchApplyService] LLM fallback error: $e');
                }
              }
            }
          }
          if (newContent == null) {
            // Неподдерживаемый diff — пропускаем без ошибки (безопасное поведение)
            print('[PatchApplyService] skip: unsupported diff for path=$path');
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
        print('[PatchApplyService] backup created at $bakPath (origLength=${original.length})');

        // применим новое содержимое
        await file.create(recursive: true);
        await file.writeAsString(newContent);
        applied++;
        print('[PatchApplyService] applied path=$path (newLength=${newContent.length})');
      }

      // успешно — фиксируем бэкап как последний
      _lastBackup = backup;
      print('[PatchApplyService] done: applied files=$applied');
      return applied;
    } catch (e) {
      print('[PatchApplyService] error: $e');
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

/// Информация из заголовка хунка
class _HunkHeaderInfo {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  _HunkHeaderInfo(this.oldStart, this.oldCount, this.newStart, this.newCount);
}

class _Hunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<String> body;
  _Hunk(this.oldStart, this.oldCount, this.newStart, this.newCount, this.body);
}

_HunkHeaderInfo? _parseHunkHeader(String headerLine) {
  // Формат: @@ -oldStart,oldCount +newStart,newCount @@ (опциональный текст)
  final re = RegExp(r"^@@ -(?<os>\d+),(?<oc>\d+) \+(?<ns>\d+),(?<nc>\d+) @@");
  final m = re.firstMatch(headerLine.trim());
  if (m == null) return null;
  int p(String name) => int.parse(m.namedGroup(name)!);
  return _HunkHeaderInfo(p('os'), p('oc'), p('ns'), p('nc'));
}

/// Пытается применить общий unified diff (с контекстом и несколькими хунками)
/// к исходному содержимому `original`. Возвращает новое содержимое или null,
/// если формат не распознан/не удалось применить.
String? _applyUnifiedDiffToContent(String original, String diff) {
  final lines = diff.split('\n');
  if (lines.isEmpty) return null;

  // Собираем hunks
  final hunks = <_Hunk>[];
  int i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.startsWith('@@')) {
      final h = _parseHunkHeader(line);
      if (h == null) return null;
      i++;
      final body = <String>[];
      while (i < lines.length && !lines[i].startsWith('@@') && !lines[i].startsWith('--- a/')) {
        final l = lines[i];
        // Разрешаем строку-метку unified diff
        if (l.startsWith('\\')) { i++; continue; }
        if (l.isNotEmpty) {
          final ch = l[0];
          if (ch != ' ' && ch != '-' && ch != '+') {
            // неизвестная строка — прерываем парсинг хунка
            break;
          }
        }
        body.add(l);
        i++;
      }
      hunks.add(_Hunk(h.oldStart, h.oldCount, h.newStart, h.newCount, body));
      continue;
    }
    i++;
  }

  if (hunks.isEmpty) {
    // Резервный кейс: иногда LLM присылает diff без @@, только заголовки и + / - строки.
    // Попробуем собрать новое содержимое из всех строк с '+', если после заголовков
    // отсутствуют контекстные строки (начинающиеся с пробела).
    int start = 0;
    // пропустим заголовки ---/+++ если есть
    if (lines.isNotEmpty && lines[0].startsWith('--- a/')) {
      if (lines.length >= 2 && lines[1].startsWith('+++ b/')) {
        start = 2;
      }
    }
    final body = lines.sublist(start);
    if (body.isEmpty) return null;
    // если встречается контекстная строка, не берёмся
    for (final l in body) {
      if (l.isEmpty) continue;
      final ch = l[0];
      if (ch != '+' && ch != '-') {
        return null;
      }
    }
    final out = <String>[];
    for (final l in body) {
      if (l.startsWith('+')) out.add(l.substring(1));
    }
    return out.join('\n');
  }

  // Контент-ориентированное применение: работаем на копии исходных строк
  final buf = original.split('\n');

  int _findContextAnchor(List<String> lines, List<String> ctx) {
    if (ctx.isEmpty) return -1;
    // Пытаемся найти все контекстные строки по порядку (с промежутками)
    int pos = 0;
    int lastIdx = -1;
    for (final c in ctx) {
      final idx = lines.indexOf(c, pos);
      if (idx == -1) return -1;
      lastIdx = idx;
      pos = idx + 1;
    }
    return lastIdx + 1; // позиция вставки — после последней контекстной строки
  }

  for (final h in hunks) {
    final ctx = <String>[];
    final dels = <String>[];
    final adds = <String>[];
    for (final l in h.body) {
      if (l.isEmpty) continue;
      if (l.startsWith('\\')) continue; // meta
      final ch = l[0];
      final content = l.substring(1);
      if (ch == ' ') ctx.add(content);
      if (ch == '-') dels.add(content);
      if (ch == '+') adds.add(content);
    }

    // 1) Определяем якорь вставки по контексту
    var insertAt = _findContextAnchor(buf, ctx);

    // 2) Удаляем строки из буфера по содержимому (в порядке появления в хунке)
    //    Ищем и удаляем ПЕРВОЕ совпадение каждый раз (стабильный порядок)
    var lastRemovalIdx = -1;
    for (final d in dels) {
      final idx = buf.indexOf(d);
      if (idx != -1) {
        buf.removeAt(idx);
        lastRemovalIdx = idx;
      }
    }

    // 3) Если якорь не найден, но были удаления — вставляем на место последнего удаления
    if (insertAt == -1 && lastRemovalIdx != -1) {
      insertAt = lastRemovalIdx;
    }

    // 4) Вставляем добавления в позицию insertAt, либо в конец файла
    if (adds.isNotEmpty) {
      if (insertAt < 0 || insertAt > buf.length) insertAt = buf.length;
      buf.insertAll(insertAt, adds);
    }
  }

  return buf.join('\n');
}
