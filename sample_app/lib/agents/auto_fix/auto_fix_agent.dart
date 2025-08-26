import 'dart:async';
import 'dart:io';

import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';

/// AutoFixAgent: анализ и предложение исправлений для файла или директории.
/// MVP каркас: возвращает заглушки и стримит базовые события пайплайна.
class AutoFixAgent implements IAgent {
  AppSettings? _settings;

  AutoFixAgent({AppSettings? initialSettings}) : _settings = initialSettings;

  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        stateful: false,
        streaming: true,
        reasoning: false,
        tools: {},
        systemPrompt: 'AutoFix agent for analyzing and fixing code. Returns unified diffs for changes.',
        responseRules: [
          'Return concise status and uncertainty when applicable',
        ],
      );

  @override
  Future<AgentResponse> ask(AgentRequest req) async {
    // MVP: просто подтверждаем получение запроса
    final u = AgentTextUtils.extractUncertainty(req.input);
    return AgentResponse(
      text: 'AutoFixAgent готов. Укажите файл или папку для анализа.',
      isFinal: true,
      mcpUsed: false,
      uncertainty: u,
      meta: {
        'note': 'stub',
      },
    );
  }

  @override
  Stream<AgentEvent> start(AgentRequest req) {
    final ctrl = StreamController<AgentEvent>();
    final runId = DateTime.now().millisecondsSinceEpoch.toString();

    Timer.run(() async {
      ctrl.add(AgentEvent(
        id: 'e1',
        runId: runId,
        stage: AgentStage.analysis_started,
        message: 'Старт анализа',
        progress: 0.1,
        meta: {
          'path': req.context?['path'] ?? '(не задано)',
          'mode': req.context?['mode'] ?? 'unknown',
        },
      ));

      final path = (req.context?['path'] as String?)?.trim() ?? '';
      final mode = (req.context?['mode'] as String?)?.trim() ?? 'file';

      List<Map<String, dynamic>> patches = [];
      List<Map<String, dynamic>> issues = [];
      try {
        final targets = <File>[];
        if (path.isNotEmpty) {
          final entity = FileSystemEntity.typeSync(path);
          if (entity == FileSystemEntityType.file) {
            targets.add(File(path));
          } else if (entity == FileSystemEntityType.directory || mode == 'dir') {
            final dir = Directory(path);
            if (await dir.exists()) {
              await for (final e in dir.list(recursive: true, followLinks: false)) {
                if (e is File && _isSupported(e.path)) targets.add(e);
              }
            }
          }
        }

        // Анализ каждой цели и формирование патчей
        for (final file in targets) {
          final res = await _analyzeAndFixFile(file);
          if (res != null) {
            issues.addAll(res.issues);
            if (res.diff.isNotEmpty) {
              patches.add({
                'path': file.path,
                'diff': res.diff,
                'newContent': res.newContent,
                'description': 'Нормализация конца файла/хвостовых пробелов',
              });
            }
          }
        }

        ctrl.add(AgentEvent(
          id: 'e2',
          runId: runId,
          stage: AgentStage.analysis_result,
          message: 'Анализ завершён, найдено проблем: ${issues.length}',
          progress: 0.7,
          meta: {
            'issues': issues,
            'filesAnalyzed': targets.length,
          },
        ));

        ctrl.add(AgentEvent(
          id: 'e3',
          runId: runId,
          stage: AgentStage.pipeline_complete,
          message: patches.isEmpty ? 'Готово: изменений нет' : 'Готово: предложено исправлений: ${patches.length}',
          progress: 1.0,
          meta: {
            'patches': patches,
            'summary': patches.isEmpty ? 'Нет изменений' : 'Предложено ${patches.length} изменений',
          },
        ));
      } catch (e) {
        ctrl.add(AgentEvent(
          id: 'err',
          runId: runId,
          stage: AgentStage.pipeline_error,
          severity: AgentSeverity.error,
          message: 'Ошибка анализа: $e',
        ));
      } finally {
        await ctrl.close();
      }
    });

    return ctrl.stream;
  }

  @override
  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  @override
  void dispose() {}

  bool _isSupported(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.dart') || p.endsWith('.md') || p.endsWith('.markdown') || p.endsWith('.java') || p.endsWith('.kt');
  }
}

class _FixResult {
  final String diff;
  final String newContent;
  final List<Map<String, dynamic>> issues;
  _FixResult(this.diff, this.newContent, this.issues);
}

Future<_FixResult?> _analyzeAndFixFile(File file) async {
  try {
    final original = await file.readAsString();
    String fixed = original;
    final issues = <Map<String, dynamic>>[];

    // Правило 1: убрать хвостовые пробелы
    final lines = fixed.split('\n');
    bool changedWhitespace = false;
    for (var i = 0; i < lines.length; i++) {
      final noTail = lines[i].replaceAll(RegExp(r"\s+$"), '');
      if (noTail != lines[i]) {
        changedWhitespace = true;
        lines[i] = noTail;
      }
    }
    if (changedWhitespace) {
      issues.add({'type': 'trailing_whitespace', 'file': file.path});
    }
    fixed = lines.join('\n');

    // Правило 2: файл должен оканчиваться переводом строки
    if (!fixed.endsWith('\n')) {
      fixed = fixed + '\n';
      issues.add({'type': 'missing_final_newline', 'file': file.path});
    }

    if (fixed == original) {
      return _FixResult('', original, issues);
    }

    final diff = _makeUnifiedDiff(file.path, original, fixed);
    return _FixResult(diff, fixed, issues);
  } catch (_) {
    return null;
  }
}

String _makeUnifiedDiff(String path, String oldContent, String newContent) {
  // Простейший unified diff: один хунк по всему файлу, без точной дифферализации.
  final oldLines = oldContent.split('\n');
  final newLines = newContent.split('\n');
  final buf = StringBuffer();
  buf.writeln('--- a/$path');
  buf.writeln('+++ b/$path');
  buf.writeln('@@ -1,${oldLines.length} +1,${newLines.length} @@');
  for (final l in oldLines) {
    buf.writeln('-$l');
  }
  for (final l in newLines) {
    buf.writeln('+$l');
  }
  return buf.toString();
}
