import 'dart:async';
import 'dart:io';

import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/domain/llm_resolver.dart';
import 'package:sample_app/utils/unified_diff_utils.dart';

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

    // Сразу сообщим о старте пайплайна, чтобы UI получил мгновенное событие
    ctrl.add(AgentEvent(
      id: 's0',
      runId: runId,
      stage: AgentStage.pipeline_start,
      message: 'Запуск AutoFix пайплайна',
      progress: 0.0,
      meta: {
        'path': req.context?['path'] ?? '',
        'mode': req.context?['mode'] ?? 'file',
      },
    ));

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

        // Нет пути или нет поддерживаемых файлов — предупредим и завершим
        if (path.isEmpty || targets.isEmpty) {
          ctrl.add(AgentEvent(
            id: 'e1w',
            runId: runId,
            stage: AgentStage.analysis_result,
            severity: AgentSeverity.warning,
            message: path.isEmpty
                ? 'Путь не задан — укажите файл или папку'
                : 'Не найдено поддерживаемых файлов для анализа',
            progress: 0.4,
            meta: {
              'filesAnalyzed': 0,
              'path': path,
              'mode': mode,
            },
          ));

          ctrl.add(AgentEvent(
            id: 'e3',
            runId: runId,
            stage: AgentStage.pipeline_complete,
            message: 'Готово: изменений нет',
            progress: 1.0,
            meta: {
              'patches': <Map<String, dynamic>>[],
              'summary': 'Нет изменений',
            },
          ));
          await ctrl.close();
          return;
        }

        // Анализ каждой цели и формирование патчей (базовые фиксы)
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

        // Необязательный LLM-этап (М2): предложения по улучшениям кода/стиля
        final useLlm = (req.context?['useLLM'] as bool?) ?? false;
        final includeLlmIntoApply = (req.context?['includeLLMInApply'] as bool?) ?? false;
        List<Map<String, dynamic>> llmPatches = [];
        if (useLlm && targets.isNotEmpty) {
          try {
            final effectiveSettings = _settings ?? const AppSettings();
            final overrideRaw = req.context?['llm_raw_override'] as String?; // для тестов
            final suggestions = overrideRaw ?? await _requestLlmSuggestions(
                files: targets, issues: issues, settings: effectiveSettings);
            if (suggestions.trim().isNotEmpty) {
              ctrl.add(AgentEvent(
                id: 'e2a',
                runId: runId,
                stage: AgentStage.analysis_result,
                message: 'LLM предложил дополнительные изменения (предпросмотр, без применения)',
                progress: 0.8,
                meta: {
                  'llm_raw': suggestions,
                },
              ));

              // Парсинг LLM unified diff по файлам
              final parsed = parseUnifiedDiffByFile(suggestions);
              // Фильтрация по поддерживаемым типам и ограничению по пути
              String _norm(String x) => File(x).absolute.path.replaceAll('\\', '/').toLowerCase();
              bool isAllowedPath(String p) {
                if (path.isEmpty) return true;
                if (mode == 'dir') {
                  return _norm(p).startsWith(_norm(path));
                } else {
                  return _norm(path) == _norm(p);
                }
              }
              for (final fp in parsed) {
                final pth = fp.path;
                if (!_isSupported(pth)) continue;
                if (!isAllowedPath(pth)) continue;
                llmPatches.add({
                  'path': pth,
                  'diff': fp.diff,
                  // newContent может быть восстановлен PatchApplyService при простом full-file diff
                });
              }
            }
          } catch (e) {
            ctrl.add(AgentEvent(
              id: 'e2e',
              runId: runId,
              stage: AgentStage.analysis_result,
              severity: AgentSeverity.warning,
              message: 'LLM предложения недоступны: $e',
              progress: 0.75,
            ));
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
          message: patches.isEmpty && (llmPatches.isEmpty || !includeLlmIntoApply)
              ? 'Готово: изменений нет'
              : 'Готово: предложено исправлений: ${patches.length + (includeLlmIntoApply ? llmPatches.length : 0)}',
          progress: 1.0,
          meta: {
            'patches': includeLlmIntoApply ? [...patches, ...llmPatches] : patches,
            'llm_patches': llmPatches,
            'summary': patches.isEmpty && (llmPatches.isEmpty || !includeLlmIntoApply)
                ? 'Нет изменений'
                : 'Предложено ${(patches.length + (includeLlmIntoApply ? llmPatches.length : 0))} изменений',
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

/// Построить промпт для LLM на основе списка файлов и найденных проблем.
String _buildLlmPrompt({required List<File> files, required List<Map<String, dynamic>> issues, int maxPreviewChars = 4000}) {
  final buf = StringBuffer();
  buf.writeln('You are a code maintenance assistant.');
  buf.writeln('Goal: propose small, safe fixes and improvements for the following files.');
  buf.writeln('Return unified diffs only, per file, when you propose changes.');
  buf.writeln('If no changes are needed, state "NO_CHANGES" for that file.');
  buf.writeln('Focus on formatting, minor style issues, comments clarity, and obvious correctness.');
  buf.writeln('Avoid large refactors. Keep diffs minimal.');
  if (issues.isNotEmpty) {
    buf.writeln('\nKnown issues:');
    for (final it in issues.take(50)) {
      buf.writeln('- ${it['type']} in ${it['file']}');
    }
  }
  for (final f in files.take(10)) {
    try {
      final content = f.readAsStringSync();
      final preview = content.length > maxPreviewChars
          ? content.substring(0, maxPreviewChars)
          : content;
      buf.writeln('\n=== FILE: ${f.path} ===');
      buf.writeln(preview);
      buf.writeln('=== END FILE ===');
    } catch (_) {
      // ignore read error for prompt
    }
  }
  buf.writeln('\nOutput format: For each file that needs changes, output a standard unified diff with headers');
  buf.writeln('"--- a/<path>" and "+++ b/<path>" and hunks starting with @@.');
  buf.writeln('For files without changes, output a single line: FILE <path>: NO_CHANGES');
  return buf.toString();
}

/// Запросить у LLM предложения по изменениям. Возвращает сырой текст ответа.
Future<String> _requestLlmSuggestions({
  required List<File> files,
  required List<Map<String, dynamic>> issues,
  required AppSettings settings,
}) async {
  final usecase = resolveLlmUseCase(settings);
  final prompt = _buildLlmPrompt(files: files, issues: issues);
  final messages = <Map<String, String>>[
    {'role': 'system', 'content': 'You are a helpful code assistant that returns unified diffs for suggested changes.'},
    {'role': 'user', 'content': prompt},
  ];
  final answer = await usecase.complete(messages: messages, settings: settings);
  return answer;
}
