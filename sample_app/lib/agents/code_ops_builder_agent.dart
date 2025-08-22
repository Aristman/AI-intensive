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

  CodeOpsBuilderAgent({AppSettings? baseSettings})
      : _settings = (baseSettings ?? const AppSettings()).copyWith(reasoningMode: true),
        _inner = CodeOpsAgent(baseSettings: (baseSettings ?? const AppSettings()).copyWith(reasoningMode: true));

  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        stateful: true,
        streaming: true,
        reasoning: true,
        tools: {'docker_exec_java', 'docker_start_java'},
      );

  @override
  void updateSettings(AppSettings settings) {
    _settings = settings.copyWith(reasoningMode: true);
    _inner.updateSettings(_settings);
  }

  @override
  void dispose() {
    // delegate cleanups if needed in future
  }

  // ===== IStatefulAgent =====
  @override
  void clearHistory() {
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

    // Regular flow: classify intent
    final intent = await _classifyIntent(userText);
    if ((intent['intent'] as String?) == 'code_generate') {
      final intentLang = (intent['language'] as String?)?.trim();
      // If no language — ask user which language to use
      if (intentLang == null || intentLang.isEmpty) {
        return AgentResponse(
          text: 'На каком языке сгенерировать код? (Автоматический запуск тестов поддержан только для Java)',
          isFinal: false,
          mcpUsed: false,
        );
      }
      final codeJson = await _requestCodeJson(userText, language: intentLang);
      if (codeJson == null) {
        return AgentResponse(text: 'Не удалось получить корректный JSON с кодом.', isFinal: true, mcpUsed: false);
      }
      final files = (codeJson['files'] as List?)
          ?.map((e) => {'path': e['path'].toString(), 'content': e['content'].toString()})
          .cast<Map<String, String>>()
          .toList();
      _pendingLanguage = codeJson['language']?.toString();
      _pendingEntrypoint = codeJson['entrypoint']?.toString();
      _pendingFiles = files;

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

    // Fallback to inner CodeOpsAgent conversation
    final res = await _inner.ask(
      userText,
      overrideResponseFormat: req.overrideFormat,
      overrideJsonSchema: req.overrideJsonSchema,
    );
    final answer = (res['answer'] as String? ?? '').trim();
    final isFinal = answer.contains(CodeOpsAgent.stopSequence);
    final clean = isFinal ? answer.replaceAll(CodeOpsAgent.stopSequence, '').trim() : answer;
    return AgentResponse(text: clean, isFinal: isFinal, mcpUsed: res['mcp_used'] == true);
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
        emit(AgentStage.pipeline_start, 'Старт пайплайна', prog: 0.0, idx: 1, total: totalSteps);

        final userText = req.input.trim();
        final intent = await _classifyIntent(userText);
        emit(AgentStage.intent_classified, 'Интент: ${intent['intent']}', prog: 0.15, idx: 1, total: totalSteps, meta: intent);

        if ((intent['intent'] as String?) != 'code_generate') {
          // Fallback to inner conversation
          final res = await _inner.ask(
            userText,
            overrideResponseFormat: req.overrideFormat,
            overrideJsonSchema: req.overrideJsonSchema,
          );
          final answer = (res['answer']?.toString() ?? '').trim();
          emit(AgentStage.pipeline_complete, answer.isEmpty ? 'Готово' : answer, prog: 1.0, idx: totalSteps, total: totalSteps, meta: {'mcp_used': res['mcp_used'] == true});
          await controller.close();
          return;
        }

        final intentLang = (intent['language'] as String?)?.trim();
        if (intentLang == null || intentLang.isEmpty) {
          emit(AgentStage.pipeline_error, 'Не указан язык. Уточните язык и повторите.', sev: AgentSeverity.warning, prog: 1.0, idx: totalSteps, total: totalSteps, meta: {'need_language': true});
          await controller.close();
          return;
        }

        emit(AgentStage.code_generation_started, 'Генерация кода...', prog: 0.35, idx: 2, total: totalSteps, meta: {'language': intentLang});
        final codeJson = await _requestCodeJson(userText, language: intentLang);
        if (codeJson == null) {
          emit(AgentStage.pipeline_error, 'Не удалось получить корректный JSON с кодом.', sev: AgentSeverity.error, prog: 1.0, idx: totalSteps, total: totalSteps);
          await controller.close();
          return;
        }

        final files = (codeJson['files'] as List?)
            ?.map((e) => {'path': e['path'].toString(), 'content': e['content'].toString()})
            .cast<Map<String, String>>()
            .toList();
        _pendingLanguage = codeJson['language']?.toString();
        _pendingEntrypoint = codeJson['entrypoint']?.toString();
        _pendingFiles = files;

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
          },
        );

        // Ask user if we should create and run tests (Java only)
        _awaitTestsConfirm = true;
        emit(
          AgentStage.ask_create_tests,
          'Создать тесты и прогнать их? (да/нет) Поддержка авто‑запуска в Docker есть только для Java.',
          prog: 0.75,
          idx: 3,
          total: totalSteps,
          meta: {'await_user': true},
        );

        emit(AgentStage.pipeline_complete, 'Ожидание подтверждения на тесты', prog: 1.0, idx: totalSteps, total: totalSteps);
        await controller.close();
      } catch (e) {
        // Any unexpected error
        emit(AgentStage.pipeline_error, 'Ошибка пайплайна: $e', sev: AgentSeverity.error, prog: 1.0);
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

  bool _isRunSuccessful(Map<String, dynamic> result) {
    try {
      final compile = result['compile'] as Map<String, dynamic>?;
      final run = result['run'] as Map<String, dynamic>?;
      final cOk = compile == null || (compile['exit_code'] == 0);
      final rOk = run == null || (run['exit_code'] == 0 && !(run['stderr']?.toString().contains('FAILURES!!!') ?? false));
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
      final compiled = (res['compile'] is Map) ? res['compile'] : null;
      final run = (res['run'] is Map) ? res['run'] : null;
      b.writeln('- ${test ?? '(unknown)'} [entrypoint: ${ep ?? '-'}]');
      if (compiled != null) {
        b.writeln('  compile: exit=${compiled['exit_code']}, stderr=${_short(compiled['stderr'])}');
      }
      if (run != null) {
        b.writeln('  run:     exit=${run['exit_code']}, stderr=${_short(run['stderr'])}');
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
    if (compile != null && (compile['exit_code'] != 0)) {
      errs.writeln('Compile errors:\n${compile['stderr'] ?? compile['stdout'] ?? ''}');
    }
    if (run != null && (run['exit_code'] != 0 || (run['stderr']?.toString().contains('FAILURES!!!') ?? false))) {
      errs.writeln('Run errors:\n${run['stderr'] ?? run['stdout'] ?? ''}');
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
    const junitHint = 'Если язык Java — генерируй тесты строго на JUnit 4: import org.junit.Test; import static org.junit.Assert.*;';
    final res = await _inner.ask(
      '$langHint $junitHint Верни строго JSON по схеме. Если требуется несколько классов/файлов — каждый в отдельном файле с полными импортами. Запрос: "${userText.replaceAll('"', '\\"')}"',
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
