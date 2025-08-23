import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/agents/code_ops_agent.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/utils/json_utils.dart';
import 'package:sample_app/utils/code_utils.dart' as cu;

/// Orchestrator agent built on top of CodeOpsAgent.
/// Implements unified IAgent interface and adds a flow:
/// 1) Generate classes on user request;
/// 2) Ask user whether to create tests;
/// 3) If confirmed and language is Java, run tests in Docker via MCP;
/// 4) Analyze results and refine tests if necessary (bounded retries).
class CodeOpsBuilderAgent implements IAgent, IToolingAgent, IStatefulAgent {
  final CodeOpsAgent _inner;
  AppSettings _settings;

  // Pending state between turns
  String? _pendingLanguage;
  String? _pendingEntrypoint;
  List<Map<String, String>>? _pendingFiles; // generated source files
  bool _awaitTestsConfirm = false; // waiting for user decision to create tests
  // Remember last code-generation prompt if language was missing
  String? _pendingCodePrompt;
  // After tests are generated, wait for explicit run confirmation (streaming)
  bool _awaitRunTestsConfirm = false;
  List<Map<String, String>>? _pendingTests; // generated test files (awaiting run)

  // Run contexts keyed by runId to persist conversation context for streaming pipelines
  final Map<String, _RunCtx> _runContexts = {};

  // Orchestrator-level short conversation history (without delegating to inner agent)
  final List<_BMsg> _history = [];

  CodeOpsBuilderAgent({AppSettings? baseSettings, CodeOpsAgent? inner})
      : _settings = (baseSettings ?? const AppSettings()).copyWith(reasoningMode: true),
        _inner = inner ?? CodeOpsAgent(baseSettings: (baseSettings ?? const AppSettings()).copyWith(reasoningMode: true));

  @override
  AgentCapabilities get capabilities => AgentCapabilities(
        stateful: true,
        streaming: true,
        reasoning: true,
        tools: const {'docker_exec_java', 'docker_start_java'},
        systemPrompt: _settings.systemPrompt,
        responseRules: const [
          'Кратко и по делу; используй списки и короткие абзацы.',
          'Используй Markdown; код — в fenced-блоках с указанием языка.',
          'Ссылайся на файлы/пути в обратных кавычках: `path/to/file`.',
          'Если неопределённость > 0.1 — задавай уточняющие вопросы перед финалом.',
        ],
      );

  @override
  void updateSettings(AppSettings settings) {
    _settings = settings.copyWith(reasoningMode: true);
    _inner.updateSettings(_settings);
  }

  // Try to extract language name from short replies like "Java", "на Java", etc.
  String? _extractLanguage(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return null;
    const langs = [
      'java', 'kotlin', 'dart', 'python', 'javascript', 'typescript', 'go', 'c#', 'c++', 'cpp', 'rust', 'swift'
    ];
    for (final l in langs) {
      if (t == l || t.contains(' $l') || t.contains('$l ') || t.contains('на $l')) {
        // normalize aliases
        if (l == 'cpp') return 'c++';
        if (l == 'javascript') return 'js';
        return l;
      }
    }
    return null;
  }

  // Heuristic: detect if user asks to generate/write/implement code/class/function
  bool _looksLikeCodeGenRequest(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return false;
    // verbs
    const verbs = [
      'сгенерируй', 'создай', 'напиши', 'реализуй', 'реализовать', 'создать', 'написать', 'сделай',
      'generate', 'create', 'write', 'implement',
    ];
    // nouns / targets
    const targets = [
      'класс', 'функци', 'метод', 'интерфейс', 'структур', 'enum', 'enums', 'struct', 'class', 'function', 'method', 'interface',
    ];
    final hasVerb = verbs.any((v) => t.contains(v));
    final hasTarget = targets.any((v) => t.contains(v));
    return hasVerb && hasTarget;
  }

  @override
  void dispose() {
    // delegate cleanups if needed in future
  }

  // ===== IStatefulAgent =====
  @override
  void clearHistory() {
    _history.clear();
    _runContexts.clear();
    _pendingLanguage = null;
    _pendingEntrypoint = null;
    _pendingFiles = null;
    _awaitTestsConfirm = false;
    _pendingCodePrompt = null;
    _awaitRunTestsConfirm = false;
    _pendingTests = null;
    // Также чистим внутреннего агента, но основной контекст хранится здесь, в оркестраторе
    _inner.clearHistory();
  }

  @override
  int get historyDepth => -1; // unknown depth (inner history is private)

  // ===== IToolingAgent =====
  @override
  bool supportsTool(String name) => {
        'docker_exec_java',
        'docker_start_java',
      }.contains(name);

  @override
  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args, {Duration? timeout}) async {
    switch (name) {
      case 'docker_exec_java':
        final files = (args['files'] as List?)?.map((e) => {
              'path': e['path'].toString(),
              'content': e['content'].toString(),
            }).cast<Map<String, String>>().toList();
        if (files == null) {
          return await _inner.execJavaInDocker(
            code: (args['code']?.toString() ?? ''),
            filename: args['filename']?.toString(),
            entrypoint: args['entrypoint']?.toString(),
            classpath: args['classpath']?.toString(),
            compileArgs: (args['compile_args'] as List?)?.cast<String>(),
            runArgs: (args['run_args'] as List?)?.cast<String>(),
            image: args['image']?.toString(),
            containerName: args['container_name']?.toString(),
            extraArgs: args['extra_args']?.toString(),
            workdir: (args['workdir']?.toString() ?? '/work'),
            timeoutMs: (args['timeout_ms'] as int?) ?? 15000,
            cpus: args['cpus'] as int?,
            memory: args['memory']?.toString(),
            cleanup: (args['cleanup']?.toString() ?? 'always'),
          );
        } else {
          return await _inner.execJavaFilesInDocker(
            files: files,
            entrypoint: args['entrypoint']?.toString(),
            classpath: args['classpath']?.toString(),
            compileArgs: (args['compile_args'] as List?)?.cast<String>(),
            runArgs: (args['run_args'] as List?)?.cast<String>(),
            image: args['image']?.toString(),
            containerName: args['container_name']?.toString(),
            extraArgs: args['extra_args']?.toString(),
            workdir: (args['workdir']?.toString() ?? '/work'),
            timeoutMs: (args['timeout_ms'] as int?) ?? 15000,
            cpus: args['cpus'] as int?,
            memory: args['memory']?.toString(),
            cleanup: (args['cleanup']?.toString() ?? 'always'),
          );
        }
      case 'docker_start_java':
        return await _inner.startLocalJavaDocker(
          containerName: args['container_name']?.toString(),
          image: args['image']?.toString(),
          port: args['port'] as int?,
          extraArgs: args['extra_args']?.toString(),
        );
      default:
        throw UnsupportedError('Unknown tool: $name');
    }
  }

  // ===== IAgent =====
  @override
  Future<AgentResponse> ask(AgentRequest req) async {
    final userText = req.input.trim();
    if (userText.isNotEmpty) {
      _history.add(_BMsg('user', userText));
    }

    // If we are waiting for tests confirmation
    if (_awaitTestsConfirm) {
      _awaitTestsConfirm = false; // consume state
      final yn = userText.toLowerCase();
      if (yn.startsWith('y') || yn.startsWith('да') || yn.contains('конечно') || yn.contains('создай')) {
        return await _handleCreateAndRunTests();
      } else {
        return AgentResponse(
          text: 'Ок, тесты создавать не будем. Готов продолжать работу с кодом.',
          isFinal: true,
          mcpUsed: false,
        );
      }
    }

    // Continuation: if we have a pending code prompt waiting for language
    final replyLang = _extractLanguage(userText);
    if (_pendingCodePrompt != null && (replyLang != null && replyLang.isNotEmpty)) {
      final codeJson = await _requestCodeJson(_pendingCodePrompt!, language: replyLang);
      if (codeJson == null) {
        return AgentResponse(text: 'Не удалось получить корректный JSON с кодом.', isFinal: true, mcpUsed: false);
      }
      var files = (codeJson['files'] as List?)
          ?.map((e) => {'path': e['path'].toString(), 'content': e['content'].toString()})
          .cast<Map<String, String>>()
          .toList();
      // Фильтруем тестовые файлы
      files = _filterOutTestFiles(files);
      _pendingLanguage = codeJson['language']?.toString() ?? replyLang;
      _pendingEntrypoint = codeJson['entrypoint']?.toString();
      _pendingFiles = files;
      _pendingCodePrompt = null; // consumed

      // Ask about tests creation
      _awaitTestsConfirm = true;
      final summary = _buildFilesSummary(files, _pendingLanguage, _pendingEntrypoint);
      return AgentResponse(
        text: '$summary\n\nСоздать тесты и прогнать их? (да/нет)\nПоддержка автозапуска через Docker есть только для Java.',
        isFinal: false,
        mcpUsed: false,
        meta: {'files': files},
      );
    }

    // Regular flow: classify intent
    final intent = await _classifyIntent(userText);
    if ((intent['intent'] as String?) == 'code_generate') {
      final intentLang = (intent['language'] as String?)?.trim();
      // If no language — ask user which language to use
      if (intentLang == null || intentLang.isEmpty) {
        // Remember prompt to reuse on next turn when language is supplied
        _pendingCodePrompt = userText;
        return AgentResponse(
          text: 'На каком языке сгенерировать код? (Автоматический запуск тестов поддержан только для Java)',
          isFinal: false,
          mcpUsed: false,
        );
      }
      // If we had pending prompt from previous turn, prefer it over current message
      final effectivePrompt = _pendingCodePrompt ?? userText;
      final codeJson = await _requestCodeJson(effectivePrompt, language: intentLang);
      if (codeJson == null) {
        return AgentResponse(text: 'Не удалось получить корректный JSON с кодом.', isFinal: true, mcpUsed: false);
      }
      var files = (codeJson['files'] as List?)
          ?.map((e) => {'path': e['path'].toString(), 'content': e['content'].toString()})
          .cast<Map<String, String>>()
          .toList();
      // Фильтруем тестовые файлы: тесты создаются отдельно, не вместе с основным кодом
      files = _filterOutTestFiles(files);
      _pendingLanguage = codeJson['language']?.toString();
      _pendingEntrypoint = codeJson['entrypoint']?.toString();
      _pendingFiles = files;
      _pendingCodePrompt = null; // consumed

      // Ask about tests creation
      _awaitTestsConfirm = true;
      final summary = _buildFilesSummary(files, _pendingLanguage, _pendingEntrypoint);
      return AgentResponse(
        text: '$summary\n\nСоздать тесты и прогнать их? (да/нет)\nПоддержка автозапуска через Docker есть только для Java.',
        isFinal: false,
        mcpUsed: false,
        meta: {'files': files},
      );
    }

    // Heuristic fallback: if it looks like a code-gen request but classifier said other
    if (_looksLikeCodeGenRequest(userText)) {
      final hLang = _extractLanguage(userText);
      if (hLang == null || hLang.isEmpty) {
        _pendingCodePrompt = userText;
        return AgentResponse(
          text: 'На каком языке сгенерировать код? (Автоматический запуск тестов поддержан только для Java)',
          isFinal: false,
          mcpUsed: false,
        );
      } else {
        final effectivePrompt = _pendingCodePrompt ?? userText;
        final codeJson = await _requestCodeJson(effectivePrompt, language: hLang);
        if (codeJson == null) {
          return AgentResponse(text: 'Не удалось получить корректный JSON с кодом.', isFinal: true, mcpUsed: false);
        }
        var files = (codeJson['files'] as List?)
            ?.map((e) => {'path': e['path'].toString(), 'content': e['content'].toString()})
            .cast<Map<String, String>>()
            .toList();
        files = _filterOutTestFiles(files);
        _pendingLanguage = codeJson['language']?.toString() ?? hLang;
        _pendingEntrypoint = codeJson['entrypoint']?.toString();
        _pendingFiles = files;
        _pendingCodePrompt = null;
        _awaitTestsConfirm = true;
        final summary = _buildFilesSummary(files, _pendingLanguage, _pendingEntrypoint);
        return AgentResponse(
          text: '$summary\n\nСоздать тесты и прогнать их? (да/нет)\nПоддержка автозапуска через Docker есть только для Java.',
          isFinal: false,
          mcpUsed: false,
          meta: {'files': files},
        );
      }
    }

    // Fallback: оркестратор не ведёт общую беседу, а управляет пайплайном CodeOps.
    // Сообщаем пользователю о поддерживаемом сценарии.
    final msg = 'Я управляю генерацией кода и тестов. Сформулируйте задачу по генерации кода (например: "Сгенерируй класс...").';
    _history.add(_BMsg('assistant', msg));
    return AgentResponse(text: msg, isFinal: true, mcpUsed: false);
  }

  @override
  Stream<AgentEvent>? start(AgentRequest req) {
    final controller = StreamController<AgentEvent>();
    final runId = _genId('run');

    Future<void>(() async {
      void emit(AgentStage stage, String message, {AgentSeverity sev = AgentSeverity.info, double? prog, int? idx, int? total, Map<String, dynamic>? meta}) {
        controller.add(AgentEvent(
          id: _genId('evt'),
          runId: runId,
          stage: stage,
          severity: sev,
          message: message,
          progress: prog,
          stepIndex: idx,
          totalSteps: total,
          meta: meta,
        ));
      }

      try {
        const totalSteps = 4; // classify -> code -> ask -> done (tests are separate turn)
        final userText = req.input.trim();
        // Save conversation context at pipeline start
        _runContexts[runId] = _RunCtx(
          runId: runId,
          userText: userText,
          startedAt: DateTime.now(),
        );
        if (userText.isNotEmpty) {
          _history.add(_BMsg('user', userText));
        }

        emit(AgentStage.pipeline_start, 'Старт пайплайна', prog: 0.0, idx: 1, total: totalSteps, meta: {
          'runId': runId,
          'startedAt': _runContexts[runId]!.startedAt.toIso8601String(),
        });

        // If we are waiting for tests confirmation, handle it in streaming mode first
        if (_awaitTestsConfirm) {
          _awaitTestsConfirm = false; // consume state
          final yn = userText.toLowerCase();
          // Negative answer -> finish pipeline immediately
          if (yn.startsWith('n') || yn.startsWith('нет')) {
            emit(AgentStage.pipeline_complete, 'Ок, тесты создавать не будем. Готов продолжать работу с кодом.', prog: 1.0, idx: totalSteps, total: totalSteps, meta: {
              'runId': runId,
              'tests': 'skipped',
            });
            final rcDone = _runContexts[runId];
            if (rcDone != null) {
              rcDone.completedAt = DateTime.now();
              rcDone.status = 'tests_skipped';
            }
            await controller.close();
            return;
          }

          // Only Java auto-run is supported
          final lang = (_pendingLanguage ?? '').toLowerCase();
          if (lang != 'java') {
            emit(AgentStage.pipeline_complete, 'Автогенерация/запуск тестов поддержан только для Java. Завершаю пайплайн.', prog: 1.0, idx: totalSteps, total: totalSteps, meta: {
              'runId': runId,
              'tests': 'unsupported_language',
              'language': _pendingLanguage,
            });
            final rcDone = _runContexts[runId];
            if (rcDone != null) {
              rcDone.completedAt = DateTime.now();
              rcDone.status = 'tests_unsupported_language';
            }
            await controller.close();
            return;
          }

          // Generate tests
          emit(AgentStage.test_generation_started, 'Генерация тестов...', prog: 0.8, idx: 3, total: totalSteps, meta: {
            'runId': runId,
            'language': _pendingLanguage,
          });
          final tests = await _generateJavaTests(_pendingFiles ?? const []);
          if (tests.isEmpty) {
            emit(AgentStage.pipeline_error, 'Не удалось сгенерировать тесты.', sev: AgentSeverity.error, prog: 1.0, idx: totalSteps, total: totalSteps, meta: {'runId': runId});
            final rcErr = _runContexts[runId];
            if (rcErr != null) {
              rcErr.completedAt = DateTime.now();
              rcErr.status = 'error_no_tests_generated';
            }
            await controller.close();
            return;
          }
          // Persist generated tests and ask user to run them explicitly (second phase)
          _pendingTests = tests;
          emit(AgentStage.test_generated, 'Тесты сгенерированы: ${tests.length}', prog: 0.85, idx: 3, total: totalSteps, meta: {
            'runId': runId,
            'tests': tests,
            'language': _pendingLanguage,
          });
          // Second-phase confirmation to actually run tests
          _awaitRunTestsConfirm = true;
          emit(
            AgentStage.ask_create_tests,
            'Запустить сгенерированные тесты? (да/нет) Тесты будут запущены вместе с исходными классами.',
            prog: 0.9,
            idx: 3,
            total: totalSteps,
            meta: {
              'await_user': true,
              'action': 'run_tests',
              'runId': runId,
              'tests_count': tests.length,
            },
          );
          await controller.close();
          return;
        }

        // If we are waiting to run previously generated tests
        if (_awaitRunTestsConfirm) {
          _awaitRunTestsConfirm = false; // consume
          final yn = userText.toLowerCase();
          if (yn.startsWith('n') || yn.startsWith('нет')) {
            emit(AgentStage.pipeline_complete, 'Запуск тестов отменён пользователем.', prog: 1.0, idx: totalSteps, total: totalSteps, meta: {
              'runId': runId,
              'tests': 'not_run',
            });
            final rcDone = _runContexts[runId];
            if (rcDone != null) {
              rcDone.completedAt = DateTime.now();
              rcDone.status = 'tests_not_run';
            }
            _pendingTests = null;
            await controller.close();
            return;
          }

          final lang = (_pendingLanguage ?? '').toLowerCase();
          if (lang != 'java') {
            emit(AgentStage.pipeline_complete, 'Автозапуск тестов поддержан только для Java. Завершаю.', prog: 1.0, idx: totalSteps, total: totalSteps, meta: {
              'runId': runId,
              'tests': 'unsupported_language',
              'language': _pendingLanguage,
            });
            final rcDone = _runContexts[runId];
            if (rcDone != null) {
              rcDone.completedAt = DateTime.now();
              rcDone.status = 'tests_unsupported_language';
            }
            _pendingTests = null;
            await controller.close();
            return;
          }

          final tests = _pendingTests ?? const <Map<String, String>>[];
          if (tests.isEmpty) {
            emit(AgentStage.pipeline_error, 'Нет сгенерированных тестов для запуска.', sev: AgentSeverity.error, prog: 1.0, idx: totalSteps, total: totalSteps, meta: {'runId': runId});
            final rcErr = _runContexts[runId];
            if (rcErr != null) {
              rcErr.completedAt = DateTime.now();
              rcErr.status = 'error_no_tests_to_run';
            }
            await controller.close();
            return;
          }

          // Run tests with deps
          var anyFailure = false;
          final runReport = <Map<String, dynamic>>[];
          for (final t in tests) {
            final deps = cu.collectTestDeps(testFile: t, pendingFiles: _pendingFiles);
            final files = (deps['files'] as List).cast<Map<String, String>>();
            final entrypoint = deps['entrypoint']?.toString();

            emit(AgentStage.docker_exec_started, 'Запуск теста: ${t['path']}', prog: 0.92, idx: 3, total: totalSteps, meta: {
              'runId': runId,
              'test': t['path'],
              'entrypoint': entrypoint,
            });
            final result = await _inner.execJavaFilesInDocker(
              files: files,
              entrypoint: entrypoint,
              timeoutMs: 20000, // align with UI _runTestWithDeps timeout
            );
            runReport.add({'test': t['path'], 'entrypoint': entrypoint, 'result': result});
            emit(AgentStage.docker_exec_result, 'Результат теста: ${t['path']}', prog: 0.94, idx: 3, total: totalSteps, meta: {
              'runId': runId,
              'test': t['path'],
              'result': result,
            });

            if (!_isRunSuccessful(result)) {
              anyFailure = true;
              emit(AgentStage.analysis_started, 'Анализ падения и попытка исправления теста', prog: 0.95, idx: 3, total: totalSteps, meta: {
                'runId': runId,
                'test': t['path'],
              });
              final refined = await _refineJavaTest(t, result);
              if (refined != null) {
                emit(AgentStage.refine_tests_started, 'Повторный запуск исправленного теста', prog: 0.96, idx: 3, total: totalSteps, meta: {
                  'runId': runId,
                  'test': refined['path'],
                });
                final deps2 = cu.collectTestDeps(testFile: refined, pendingFiles: _pendingFiles);
                final files2 = (deps2['files'] as List).cast<Map<String, String>>();
                final ep2 = deps2['entrypoint']?.toString();
                final result2 = await _inner.execJavaFilesInDocker(
                  files: files2,
                  entrypoint: ep2,
                  timeoutMs: 20000, // align with UI _runTestWithDeps timeout
                );
                runReport.add({'test': refined['path'], 'entrypoint': ep2, 'result': result2, 'refined': true});
                emit(AgentStage.refine_tests_result, 'Результат исправленного теста: ${refined['path']}', prog: 0.97, idx: 3, total: totalSteps, meta: {
                  'runId': runId,
                  'test': refined['path'],
                  'result': result2,
                });
              }
            }
          }

          // Complete pipeline now
          final allGreen = !anyFailure;
          emit(AgentStage.pipeline_complete, allGreen ? 'Все тесты успешно прошли' : 'Есть падающие тесты', prog: 1.0, idx: totalSteps, total: totalSteps, meta: {
            'runId': runId,
            'all_green': allGreen,
            'report': runReport,
          });
          final rcDone = _runContexts[runId];
          if (rcDone != null) {
            rcDone.completedAt = DateTime.now();
            rcDone.status = allGreen ? 'tests_green' : 'tests_failed';
          }
          _pendingTests = null;
          await controller.close();
          return;
        }

        // Continuation branch for streaming mode: if previous turn lacked language
        final contLang = _extractLanguage(userText);
        if (_pendingCodePrompt != null && (contLang != null && contLang.isNotEmpty)) {
          // We have pending prompt and the user supplied the language now.
          emit(AgentStage.intent_classified, 'Интент: code_generate', prog: 0.15, idx: 1, total: totalSteps, meta: {
            'intent': 'code_generate',
            'language': contLang,
            'reason': 'continuation_language_supplied',
          });

          // Update run context
          final rc0 = _runContexts[runId];
          if (rc0 != null) {
            rc0.intent = 'code_generate';
            rc0.language = contLang;
          }

          emit(AgentStage.code_generation_started, 'Генерация кода...', prog: 0.35, idx: 2, total: totalSteps, meta: {
            'language': contLang,
          });

          final codeJson = await _requestCodeJson(_pendingCodePrompt!, language: contLang);
          if (codeJson == null) {
            emit(AgentStage.pipeline_error, 'Не удалось получить корректный JSON с кодом.', sev: AgentSeverity.error, prog: 1.0, idx: totalSteps, total: totalSteps, meta: {
              'runId': runId,
            });
            final rcErr = _runContexts[runId];
            if (rcErr != null) {
              rcErr.completedAt = DateTime.now();
              rcErr.status = 'error_bad_code_json';
            }
            await controller.close();
            return;
          }

          var files = (codeJson['files'] as List?)
              ?.map((e) => {'path': e['path'].toString(), 'content': e['content'].toString()})
              .cast<Map<String, String>>()
              .toList();
          files = _filterOutTestFiles(files);
          _pendingLanguage = codeJson['language']?.toString() ?? contLang;
          _pendingEntrypoint = codeJson['entrypoint']?.toString();
          _pendingFiles = files;
          _pendingCodePrompt = null; // consumed

          // Update run context with generated details
          final rc1 = _runContexts[runId];
          if (rc1 != null) {
            rc1.language = _pendingLanguage ?? rc1.language;
            rc1.entrypoint = _pendingEntrypoint;
            rc1.files = files;
          }

          emit(
            AgentStage.code_generated,
            'Код сгенерирован: файлов=${files?.length ?? 0}, язык=${_pendingLanguage ?? '-'}',
            prog: 0.6,
            idx: 2,
            total: totalSteps,
            meta: {
              'language': _pendingLanguage,
              'entrypoint': _pendingEntrypoint,
              'files': files,
              'runId': runId,
            },
          );

          // Ask user to create tests
          _awaitTestsConfirm = true;
          emit(
            AgentStage.ask_create_tests,
            'Создать тесты и прогнать их? (да/нет) Поддержка авто‑запуска в Docker есть только для Java.',
            prog: 0.75,
            idx: 3,
            total: totalSteps,
            meta: {'await_user': true, 'action': 'create_tests', 'runId': runId},
          );

          // Mark run context, do not complete pipeline here
          final rcDone = _runContexts[runId];
          if (rcDone != null) {
            rcDone.status = 'await_tests_confirm';
          }
          await controller.close();
          return;
        }

        final intent = await _classifyIntent(userText);
        emit(AgentStage.intent_classified, 'Интент: ${intent['intent']}', prog: 0.15, idx: 1, total: totalSteps, meta: intent);
        // Update run context with intent and (possible) language
        final rc1 = _runContexts[runId];
        if (rc1 != null) {
          rc1.intent = intent['intent']?.toString();
          rc1.language = (intent['language'] as String?)?.trim();
        }

        if ((intent['intent'] as String?) != 'code_generate') {
          // Heuristic: treat as code-gen if it looks like so
          if (_looksLikeCodeGenRequest(userText)) {
            final hLang = _extractLanguage(userText);
            if (hLang == null || hLang.isEmpty) {
              emit(AgentStage.pipeline_error, 'Не указан язык. Уточните язык и повторите.', sev: AgentSeverity.warning, prog: 1.0, idx: totalSteps, total: totalSteps, meta: {
                'need_language': true,
                'runId': runId,
              });
              final rcErr = _runContexts[runId];
              if (rcErr != null) {
                rcErr.completedAt = DateTime.now();
                rcErr.status = 'error_need_language';
              }
              _pendingCodePrompt = userText; // remember for next non-stream or stream call
              await controller.close();
              return;
            } else {
              emit(AgentStage.intent_classified, 'Интент: code_generate', prog: 0.15, idx: 1, total: totalSteps, meta: {
                'intent': 'code_generate',
                'language': hLang,
                'reason': 'heuristic_override',
              });
              emit(AgentStage.code_generation_started, 'Генерация кода...', prog: 0.35, idx: 2, total: totalSteps, meta: {'language': hLang});
              final effectivePrompt = _pendingCodePrompt ?? userText;
              final codeJson = await _requestCodeJson(effectivePrompt, language: hLang);
              if (codeJson == null) {
                emit(AgentStage.pipeline_error, 'Не удалось получить корректный JSON с кодом.', sev: AgentSeverity.error, prog: 1.0, idx: totalSteps, total: totalSteps, meta: {
                  'runId': runId,
                });
                final rcErr2 = _runContexts[runId];
                if (rcErr2 != null) {
                  rcErr2.completedAt = DateTime.now();
                  rcErr2.status = 'error_bad_code_json';
                }
                await controller.close();
                return;
              }
              var files = (codeJson['files'] as List?)
                  ?.map((e) => {'path': e['path'].toString(), 'content': e['content'].toString()})
                  .cast<Map<String, String>>()
                  .toList();
              files = _filterOutTestFiles(files);
              _pendingLanguage = codeJson['language']?.toString() ?? hLang;
              _pendingEntrypoint = codeJson['entrypoint']?.toString();
              _pendingFiles = files;
              _pendingCodePrompt = null;

              final rc2 = _runContexts[runId];
              if (rc2 != null) {
                rc2.language = _pendingLanguage ?? rc2.language;
                rc2.entrypoint = _pendingEntrypoint;
                rc2.files = files;
              }

              emit(AgentStage.code_generated, 'Код сгенерирован: файлов=${files?.length ?? 0}, язык=${_pendingLanguage ?? '-'}', prog: 0.6, idx: 2, total: totalSteps, meta: {
                'language': _pendingLanguage,
                'entrypoint': _pendingEntrypoint,
                'files': files,
                'runId': runId,
              });
              _awaitTestsConfirm = true;
              emit(AgentStage.ask_create_tests, 'Создать тесты и прогнать их? (да/нет) Поддержка авто‑запуска в Docker есть только для Java.', prog: 0.75, idx: 3, total: totalSteps, meta: {
                'await_user': true,
                'runId': runId,
              });
              final rcDone = _runContexts[runId];
              if (rcDone != null) {
                rcDone.status = 'await_tests_confirm';
              }
              await controller.close();
              return;
            }
          }

          // Fallback to inner conversation
          final res = await _inner.ask(
            userText,
            overrideResponseFormat: req.overrideFormat,
            overrideJsonSchema: req.overrideJsonSchema,
          );
          final answer = (res['answer']?.toString() ?? '').trim();
          emit(AgentStage.pipeline_complete, answer.isEmpty ? 'Готово' : answer, prog: 1.0, idx: totalSteps, total: totalSteps, meta: {
            'mcp_used': res['mcp_used'] == true,
            'runId': runId,
          });
          final rcDone = _runContexts[runId];
          if (rcDone != null) {
            rcDone.completedAt = DateTime.now();
            rcDone.status = 'complete';
          }
          await controller.close();
          return;
        }

        final intentLang = (intent['language'] as String?)?.trim();
        if (intentLang == null || intentLang.isEmpty) {
          emit(AgentStage.pipeline_error, 'Не указан язык. Уточните язык и повторите.', sev: AgentSeverity.warning, prog: 1.0, idx: totalSteps, total: totalSteps, meta: {
            'need_language': true,
            'runId': runId,
          });
          final rcErr = _runContexts[runId];
          if (rcErr != null) {
            rcErr.completedAt = DateTime.now();
            rcErr.status = 'error_need_language';
          }
          // Remember prompt for subsequent non-stream continuation
          _pendingCodePrompt = userText;
          await controller.close();
          return;
        }

        emit(AgentStage.code_generation_started, 'Генерация кода...', prog: 0.35, idx: 2, total: totalSteps, meta: {'language': intentLang});
        final codeJson = await _requestCodeJson(userText, language: intentLang);
        if (codeJson == null) {
          emit(AgentStage.pipeline_error, 'Не удалось получить корректный JSON с кодом.', sev: AgentSeverity.error, prog: 1.0, idx: totalSteps, total: totalSteps, meta: {
            'runId': runId,
          });
          final rcErr2 = _runContexts[runId];
          if (rcErr2 != null) {
            rcErr2.completedAt = DateTime.now();
            rcErr2.status = 'error_bad_code_json';
          }
          await controller.close();
          return;
        }

        var files = (codeJson['files'] as List?)
            ?.map((e) => {'path': e['path'].toString(), 'content': e['content'].toString()})
            .cast<Map<String, String>>()
            .toList();
        // Фильтруем тестовые файлы
        files = _filterOutTestFiles(files);
        _pendingLanguage = codeJson['language']?.toString();
        _pendingEntrypoint = codeJson['entrypoint']?.toString();
        _pendingFiles = files;

        // Update run context with generated details
        final rc2 = _runContexts[runId];
        if (rc2 != null) {
          rc2.language = _pendingLanguage ?? rc2.language;
          rc2.entrypoint = _pendingEntrypoint;
          rc2.files = files;
        }

        emit(
          AgentStage.code_generated,
          'Код сгенерирован: файлов=${files?.length ?? 0}, язык=${_pendingLanguage ?? '-'}',
          prog: 0.6,
          idx: 2,
          total: totalSteps,
          meta: {
            'language': _pendingLanguage,
            'entrypoint': _pendingEntrypoint,
            'files': files,
            'runId': runId,
          },
        );

        // Ask user if we should create and run tests (Java only)
        _awaitTestsConfirm = true;
        _pendingCodePrompt = null; // completed code gen
        emit(
          AgentStage.ask_create_tests,
          'Создать тесты и прогнать их? (да/нет) Поддержка авто‑запуска в Docker есть только для Java.',
          prog: 0.75,
          idx: 3,
          total: totalSteps,
          meta: {'await_user': true, 'runId': runId},
        );
        final rcWait = _runContexts[runId];
        if (rcWait != null) {
          rcWait.status = 'await_tests_confirm';
        }
        await controller.close();
      } catch (e) {
        // Any unexpected error
        emit(AgentStage.pipeline_error, 'Ошибка пайплайна: $e', sev: AgentSeverity.error, prog: 1.0, meta: {
          'runId': runId,
        });
        final rcErr3 = _runContexts[runId];
        if (rcErr3 != null) {
          rcErr3.completedAt = DateTime.now();
          rcErr3.status = 'error_unexpected';
        }
        await controller.close();
      }
    });

    return controller.stream;
  }

  String _genId(String prefix) {
    final r = Random();
    final n = DateTime.now().microsecondsSinceEpoch ^ r.nextInt(1 << 31);
    return '$prefix-$n';
  }

  String _buildFilesSummary(List<Map<String, String>>? files, String? language, String? entrypoint) {
    if (files == null || files.isEmpty) {
      return 'Сгенерирован код (файлы не обнаружены). Язык: ${language ?? '-'}';
    }
    final header = files.length > 1
        ? 'Сгенерировано файлов: ${files.length}. Язык: ${language ?? '-'}\nEntrypoint: ${entrypoint ?? '-'}'
        : 'Сгенерирован файл. Язык: ${language ?? '-'}\nEntrypoint: ${entrypoint ?? '-'}';
    final list = files.map((f) => '- ${f['path']}').join('\n');
    return '$header\n$list';
  }

  Future<AgentResponse> _handleCreateAndRunTests() async {
    if ((_pendingFiles?.isEmpty ?? true) || (_pendingLanguage == null)) {
      return AgentResponse(text: 'Нет сгенерированных файлов для тестирования.', isFinal: true, mcpUsed: false);
    }
    // Only Java tests are supported for auto-run
    if (_pendingLanguage!.toLowerCase() != 'java') {
      return AgentResponse(
        text: 'Создание/запуск тестов автоматически поддержан только для Java. Продолжить вручную.',
        isFinal: true,
        mcpUsed: false,
      );
    }

    // 1) Generate tests for provided Java files (JUnit4)
    final tests = await _generateJavaTests(_pendingFiles!);
    if (tests.isEmpty) {
      return AgentResponse(text: 'Не удалось сгенерировать тесты для Java.', isFinal: true, mcpUsed: false);
    }

    // 2) Run tests one-by-one with dependencies
    final runReport = <Map<String, dynamic>>[];
    var anyFailure = false;
    for (final t in tests) {
      final deps = cu.collectTestDeps(testFile: t, pendingFiles: _pendingFiles);
      final files = (deps['files'] as List).cast<Map<String, String>>();
      final entrypoint = deps['entrypoint']?.toString();
      final result = await _inner.execJavaFilesInDocker(files: files, entrypoint: entrypoint);
      runReport.add({'test': t['path'], 'entrypoint': entrypoint, 'result': result});
      if (!_isRunSuccessful(result)) {
        anyFailure = true;
        // 3) Attempt to refine tests based on failure and retry once per failing test
        final refined = await _refineJavaTest(t, result);
        if (refined != null) {
          final deps2 = cu.collectTestDeps(testFile: refined, pendingFiles: _pendingFiles);
          final files2 = (deps2['files'] as List).cast<Map<String, String>>();
          final ep2 = deps2['entrypoint']?.toString();
          final result2 = await _inner.execJavaFilesInDocker(files: files2, entrypoint: ep2);
          runReport.add({'test': refined['path'], 'entrypoint': ep2, 'result': result2, 'refined': true});
          if (!_isRunSuccessful(result2)) {
            // still failing — keep it in report
            anyFailure = true;
          }
        }
      }
    }

    final reportText = _formatRunReport(runReport);
    return AgentResponse(
      text: anyFailure
          ? 'Тесты запущены, обнаружены проблемы. Отчёт:\n$reportText'
          : 'Все тесты успешно прошли. Отчёт:\n$reportText',
      isFinal: true,
      mcpUsed: true,
      meta: {'report': runReport},
    );
  }

  int? _exitCodeOf(Map<String, dynamic>? m) {
    if (m == null) return null;
    final v = m['exit_code'] ?? m['exitCode'];
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  String? _stderrOf(Map<String, dynamic>? m) => m?['stderr']?.toString();
  String? _stdoutOf(Map<String, dynamic>? m) => m?['stdout']?.toString();

  bool _hasFailuresMarker(Map<String, dynamic>? m) {
    final s = _stderrOf(m);
    return s?.contains('FAILURES!!!') ?? false;
  }

  bool _isRunSuccessful(Map<String, dynamic> result) {
    try {
      final compile = result['compile'] as Map<String, dynamic>?;
      final run = result['run'] as Map<String, dynamic>?;
      final cOk = compile == null || ((_exitCodeOf(compile) ?? 0) == 0);
      final rOk = run == null || (((_exitCodeOf(run) ?? 0) == 0) && !_hasFailuresMarker(run));
      return cOk && rOk;
    } catch (_) {
      return false;
    }
  }

  String _formatRunReport(List<Map<String, dynamic>> report) {
    final b = StringBuffer();
    for (final item in report) {
      final test = item['test'];
      final ep = item['entrypoint'];
      final res = item['result'] as Map<String, dynamic>;
      final compiled = (res['compile'] is Map) ? res['compile'] as Map<String, dynamic> : null;
      final run = (res['run'] is Map) ? res['run'] as Map<String, dynamic> : null;
      b.writeln('- ${test ?? '(unknown)'} [entrypoint: ${ep ?? '-'}]');
      if (compiled != null) {
        b.writeln('  compile: exit=${_exitCodeOf(compiled)}, stderr=${_short(_stderrOf(compiled))}');
      }
      if (run != null) {
        b.writeln('  run:     exit=${_exitCodeOf(run)}, stderr=${_short(_stderrOf(run))}');
      }
      if (item['refined'] == true) b.writeln('  (refined and retried)');
    }
    return b.toString().trim();
  }

  String _short(Object? s, {int limit = 160}) {
    final t = s?.toString() ?? '';
    if (t.length <= limit) return t;
    return '${t.substring(0, limit)}...';
  }

  Future<List<Map<String, String>>> _generateJavaTests(List<Map<String, String>> files) async {
    // Prepare compact context for LLM
    final parts = files.map((f) => 'FILE ${f['path']}\n${_clip(f['content'], 1200)}').join('\n\n');
    const schema = '{"tests":"Array<{path:string,content:string}>","note":"string?"}';
    final prompt = 'Сгенерируй минимальные, но корректные JUnit 4 тесты для следующих Java классов.\n'
        'Требования: импорты org.junit.Test и static org.junit.Assert.*; один публичный тестовый класс на файл; корректные package и имена.\n'
        'Верни строго JSON по схеме: $schema\n\n$parts';
    final res = await _inner.ask(
      prompt,
      overrideResponseFormat: ResponseFormat.json,
      overrideJsonSchema: schema,
    );
    final answer = res['answer']?.toString() ?? '';
    final map = tryExtractJsonMap(answer);
    final list = (map != null ? map['tests'] as List? : null) ?? const [];
    final tests = list
        .map((e) => {
              'path': e['path'].toString(),
              'content': e['content'].toString(),
            })
        .cast<Map<String, String>>()
        .toList();
    return tests;
  }

  Future<Map<String, String>?> _refineJavaTest(Map<String, String> testFile, Map<String, dynamic> result) async {
    final compile = result['compile'] as Map<String, dynamic>?;
    final run = result['run'] as Map<String, dynamic>?;
    final errs = StringBuffer();
    if (compile != null && ((_exitCodeOf(compile) ?? 0) != 0)) {
      errs.writeln('Compile errors:\n${_stderrOf(compile) ?? _stdoutOf(compile) ?? ''}');
    }
    if (run != null && (((_exitCodeOf(run) ?? 0) != 0) || _hasFailuresMarker(run))) {
      errs.writeln('Run errors:\n${_stderrOf(run) ?? _stdoutOf(run) ?? ''}');
    }
    final errText = errs.toString().trim();
    if (errText.isEmpty) return null;

    const schema = '{"path":"string","content":"string"}';
    final prompt = 'По следующим ошибкам доработай тест JUnit 4.\n'
        'Верни строго JSON: $schema. Сохрани package и имя класса.\n'
        'Ошибки:\n${_clip(errText, 1800)}\n\nТекущий тест (${testFile['path']}):\n${_clip(testFile['content'] ?? '', 1800)}';
    final res = await _inner.ask(
      prompt,
      overrideResponseFormat: ResponseFormat.json,
      overrideJsonSchema: schema,
    );
    final answer = res['answer']?.toString() ?? '';
    final map = tryExtractJsonMap(answer);
    if (map == null) return null;
    return {
      'path': map['path'].toString(),
      'content': map['content'].toString(),
    };
  }

  Future<Map<String, dynamic>> _classifyIntent(String userText) async {
    const schema = '{"intent":"code_generate|other","language":"string?","reason":"string"}';
    final res = await _inner.ask(
      'Классифицируй запрос как code_generate или other. Ответь строго по схеме. Запрос: "${userText.replaceAll('"', '\\"')}"',
      overrideResponseFormat: ResponseFormat.json,
      overrideJsonSchema: schema,
    );
    final answer = res['answer'] as String? ?? '';
    try {
      final m = jsonDecode(answer) as Map<String, dynamic>;
      return m;
    } catch (_) {
      return {'intent': 'other', 'reason': 'failed_to_parse'};
    }
  }

  Future<Map<String, dynamic>?> _requestCodeJson(String userText, {String? language}) async {
    const codeSchema = '{"title":"string","description":"string","language":"string","entrypoint":"string?","files":"Array<{path:string,content:string}>"}';
    final langHint = (language != null && language.trim().isNotEmpty)
        ? 'Сгенерируй код на языке ${language.trim()}.'
        : 'Если язык явно не указан — задай уточняющий вопрос. Не возвращай итог, пока язык не подтверждён.';
    const noTestsHint = 'Не добавляй тестовые файлы в результат. Тесты будут запрошены отдельно.';
    final res = await _inner.ask(
      '$langHint $noTestsHint Верни строго JSON по схеме. Если требуется несколько классов/файлов — каждый в отдельном файле с полными импортами. Запрос: "${userText.replaceAll('"', '\\"')}"',
      overrideResponseFormat: ResponseFormat.json,
      overrideJsonSchema: codeSchema,
    );
    final answer = res['answer'] as String? ?? '';
    final jsonMap = tryExtractJsonMap(answer);
    if (jsonMap == null) return null;
    if (!jsonMap.containsKey('files') && jsonMap.containsKey('code')) {
      final fname = (jsonMap['filename']?.toString().isNotEmpty ?? false) ? jsonMap['filename'].toString() : 'Main.java';
      final content = jsonMap['code']?.toString() ?? '';
      jsonMap['files'] = [
        {
          'path': fname,
          'content': content,
        }
      ];
    }
    return jsonMap;
  }

  String _clip(String? s, int max) {
    final t = (s ?? '').trim();
    return t.length <= max ? t : '${t.substring(0, max)}...';
  }
}

List<Map<String, String>>? _filterOutTestFiles(List<Map<String, String>>? files) {
  if (files == null) return null;
  bool looksLikeTest(Map<String, String> f) {
    final p = (f['path'] ?? '').toLowerCase();
    final c = (f['content'] ?? '').toLowerCase();
    if (p.endsWith('test.java') || p.contains('/test/') || p.contains('\\test\\')) return true;
    if (c.contains('org.junit') || c.contains('@test')) return true;
    return false;
  }
  return files.where((f) => !looksLikeTest(f)).toList();
}

class _BMsg {
  final String role; // 'user' | 'assistant'
  final String content;
  _BMsg(this.role, this.content);
}

class _RunCtx {
  final String runId;
  final String userText;
  final DateTime startedAt;
  String? intent;
  String? language;
  String? entrypoint;
  List<Map<String, String>>? files;
  String? status; // complete | error_* | await_tests_confirm | ...
  DateTime? completedAt;

  _RunCtx({
    required this.runId,
    required this.userText,
    required this.startedAt,
  });
}
