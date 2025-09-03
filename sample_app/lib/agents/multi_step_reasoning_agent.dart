import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/domain/llm_resolver.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/mcp_client.dart';
import 'package:sample_app/services/conversation_storage_service.dart';

/// Минимальная реализация многоэтапного агента по схеме:
/// Анализ -> План -> Исполнение/Проверка -> Синтез -> Рефлексия
/// С фокусом на неблокирующий UI и безопасные фолбэки.
class MultiStepReasoningAgent implements IAgent, IStatefulAgent, IToolingAgent {
  final ConversationStorageService _store = ConversationStorageService();
  final List<Map<String, String>> _history = [];
  AppSettings _settings;
  final String conversationKey;

  MultiStepReasoningAgent({required AppSettings settings, required this.conversationKey})
      : _settings = settings;

  // ===== IAgent =====
  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        stateful: true,
        streaming: true,
        reasoning: true,
        tools: {'search_web', 'calculate', 'get_current_date'},
        systemPrompt: 'Многоэтапный агент: анализ запроса, планирование, инструментальные шаги, проверка, синтез и рефлексия.',
        responseRules: [
          'Использовать строгий JSON на внутренних шагах',
          'Минимизировать галлюцинации через проверку фактов',
        ],
      );

  @override
  Future<AgentResponse> ask(AgentRequest req) async {
    // Одношаговый режим: запустить конвейер и дождаться финального результата
    final stream = start(req);
    if (stream == null) {
      return const AgentResponse(text: 'Ошибка: streaming недоступен', isFinal: true);
    }

  Map<String, dynamic> _normalizeToolArgs(String tool, dynamic input) {
    // Привести вход шага к карте аргументов, учитывая частые случаи строкового ввода
    if (input is Map<String, dynamic>) return input;
    switch (tool) {
      case 'search_web':
        return {'queryText': input?.toString() ?? ''};
      case 'calculate':
        return {'expression': input?.toString() ?? ''};
      case 'get_current_date':
        return <String, dynamic>{};
      default:
        return {'input': input};
    }
  }
    late final Completer<AgentResponse> done = Completer();
    Map<String, dynamic>? synth;
    stream.listen((e) {
      if (e.stage == AgentStage.pipeline_complete) {
        final text = (e.meta?['finalText'] as String?) ?? '';
        final used = (e.meta?['mcpUsed'] as bool?) ?? false;
        synth = {'text': text, 'mcp': used};
      }
    }, onError: (err) {
      if (!done.isCompleted) {
        done.complete(AgentResponse(text: 'Ошибка: $err', isFinal: true));
      }
    }, onDone: () {
      if (!done.isCompleted) {
        done.complete(AgentResponse(text: (synth?['text'] ?? '') as String, isFinal: true, mcpUsed: (synth?['mcp'] ?? false) as bool));
      }
    });
    return done.future;
  }

  @override
  Stream<AgentEvent>? start(AgentRequest req) {
    return _runPipeline(req).asStream().expand((events) => events);
  }

  @override
  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  @override
  void dispose() {}

  // ===== IStatefulAgent =====
  @override
  void clearHistory() {
    _history.clear();
  }

  @override
  int get historyDepth => _settings.historyDepth;

  // ===== IToolingAgent =====
  @override
  bool supportsTool(String name) => {'search_web', 'calculate', 'get_current_date'}.contains(name);

  @override
  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args, {Duration? timeout}) async {
    switch (name) {
      case 'get_current_date':
        return {'now': DateTime.now().toIso8601String()};
      case 'calculate':
        final expr = (args['expression'] ?? '').toString();
        final val = _safeEval(expr);
        return {'expression': expr, 'result': val};
      case 'search_web':
        return await _callMcpSearch(args, timeout: timeout);
      default:
        throw StateError('Tool not found: $name');
    }
  }

  // ===== Internal pipeline =====
  Future<List<AgentEvent>> _runPipeline(AgentRequest req) async {
    final runId = DateTime.now().millisecondsSinceEpoch.toString();
    final events = <AgentEvent>[];

    void emit(AgentStage stage, String msg, {double? progress, int? step, int? total, Map<String, dynamic>? meta}) {
      events.add(AgentEvent(
        id: '${stage.name}-${events.length + 1}',
        runId: runId,
        stage: stage,
        message: msg,
        progress: progress,
        stepIndex: step,
        totalSteps: total,
        meta: meta,
      ));
    }

    emit(AgentStage.pipeline_start, 'Старт конвейера', progress: 0.0);

    // 1. Прием/история
    _history.add({'role': 'user', 'content': req.input});
    if (_history.length > historyDepth) {
      _history.removeRange(0, _history.length - historyDepth);
    }
    await _store.save(conversationKey, _history);

    // 2. Анализ/Планирование
    emit(AgentStage.analysis_started, '🤔 Анализ запроса', progress: 0.1, step: 1, total: 5);
    final plan = await _analyzeAndPlan(req);
    emit(AgentStage.analysis_result, 'Сформирован план из ${plan.steps.length} шаг(ов) и инструменты: ${plan.tools.join(', ')}', progress: 0.2, step: 1, total: 5, meta: plan.toJson());

    // 3. Исполнение + 4. Валидация
    final validated = <Map<String, dynamic>>[];
    var mcpUsed = false;
    for (var i = 0; i < plan.steps.length; i++) {
      final s = plan.steps[i];
      emit(AgentStage.docker_exec_started, '🔍 Исполнение шага ${i + 1}: ${s['title'] ?? s['tool']}', progress: 0.2 + (0.6 * i / max(1, plan.steps.length)), step: 2, total: 5, meta: s);
      Map<String, dynamic> toolRes = {};
      try {
        final args = _normalizeToolArgs(s['tool'] as String, s['input']);
        toolRes = await callTool(s['tool'] as String, args, timeout: req.timeout);
        if (s['tool'] == 'search_web') mcpUsed = true;
      } catch (e) {
        toolRes = {'error': e.toString()};
      }

      emit(AgentStage.docker_exec_result, 'Результат шага ${i + 1} получен', meta: {'step': s, 'result': toolRes});

      // Верификация
      emit(AgentStage.refine_tests_started, '✅ Проверка шага ${i + 1}', meta: {'step': s});
      final v = await _validateStep(req, s, toolRes);
      emit(AgentStage.refine_tests_result, v['isRelevant'] == true ? 'Шаг ${i + 1}: валиден (conf=${v['confidence']})' : 'Шаг ${i + 1}: невалиден — будет пропущен', meta: v);
      if (v['isRelevant'] == true) {
        validated.add({'step': s, 'result': toolRes, 'validation': v});
      }
    }

    // 5. Синтез
    emit(AgentStage.test_generation_started, '📝 Синтез ответа', progress: 0.85, step: 4, total: 5);
    final finalText = await _synthesize(req, plan, validated);

    // 6. Рефлексия
    emit(AgentStage.code_generation_started, '♻️ Рефлексия', progress: 0.95, step: 5, total: 5);
    final reflection = await _reflect(req, finalText, plan, validated);

    // Финал
    emit(AgentStage.pipeline_complete, 'Готово', progress: 1.0, meta: {
      'finalText': finalText,
      'reflection': reflection,
      'mcpUsed': mcpUsed,
    });

    // Сохранить в историю финальный ответ
    _history.add({'role': 'assistant', 'content': finalText});
    if (_history.length > historyDepth) {
      _history.removeRange(0, _history.length - historyDepth);
    }
    await _store.save(conversationKey, _history);

    return events;
  }

  // ===== Steps impl =====
  Future<_Plan> _analyzeAndPlan(AgentRequest req) async {
    final usecase = resolveLlmUseCase(_settings);
    final sys = 'Ты — планировщик. Разбери пользовательский запрос на интент, тип, потребности и составь JSON с полями: intent, type, needs[], plan[], tools[]. plan[] — массив шагов вида {id, title, description, tool, input}. Разрешённые tool: search_web, calculate, get_current_date.';
    final messages = [
      {'role': 'system', 'content': sys},
      ..._history,
    ];
    String raw;
    try {
      raw = await usecase.complete(messages: messages, settings: _settings);
    } catch (e) {
      // Фолбэк — минимальный план, чтобы не падать UI
      return _Plan(steps: [
        {'id': 1, 'title': 'Определение даты', 'tool': 'get_current_date', 'input': {}},
      ], tools: ['get_current_date']);
    }
    final parsed = _tryParseJson(raw);
    if (parsed == null) {
      // Вырезать fenced JSON, если есть
      final fenced = _extractFencedJson(raw);
      final p2 = fenced != null ? _tryParseJson(fenced) : null;
      if (p2 == null) {
        return _Plan(steps: [
          {'id': 1, 'title': 'Определение даты', 'tool': 'get_current_date', 'input': {}},
        ], tools: ['get_current_date']);
      }
      return _Plan.fromJson(p2);
    }
    return _Plan.fromJson(parsed);
  }

  Future<Map<String, dynamic>> _validateStep(AgentRequest req, Map<String, dynamic> step, Map<String, dynamic> toolRes) async {
    final usecase = resolveLlmUseCase(_settings);
    final sys = 'Ты — валидатор фактов. На вход: исходный запрос пользователя, описание шага и результат инструмента. Верни СТРОГИЙ JSON: {"isRelevant": bool, "confidence": number, "reason": string}.';
    final messages = [
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': 'Запрос: ${req.input}\nШаг: ${step}\nРезультат: ${toolRes}'}
    ];
    try {
      final raw = await usecase.complete(messages: messages, settings: _settings);
      final parsed = _tryParseJson(raw) ?? _tryParseJson(_extractFencedJson(raw));
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    return {"isRelevant": true, "confidence": 0.5, "reason": "fallback"};
  }

  Future<String> _synthesize(AgentRequest req, _Plan plan, List<Map<String, dynamic>> validated) async {
    final usecase = resolveLlmUseCase(_settings);
    final sys = 'Ты — синтезатор ответа. На вход: исходный запрос, итоговый план и проверенные данные. Верни краткий структурированный ответ на русском. Используй Markdown (заголовки, списки, ссылки).';
    final messages = [
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': 'Запрос: ${req.input}\nПлан: ${plan.toJson()}\nДанные: ${validated}'}
    ];
    try {
      return await usecase.complete(messages: messages, settings: _settings);
    } catch (_) {
      return 'Не удалось сгенерировать ответ.';
    }
  }

  Future<String> _reflect(AgentRequest req, String finalText, _Plan plan, List<Map<String, dynamic>> validated) async {
    final usecase = resolveLlmUseCase(_settings);
    final sys = 'Короткая рефлексия: оцени полноту ответа (кратко) и возможные улучшения. 1-2 предложения. Русский язык.';
    final messages = [
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': 'Запрос: ${req.input}\nОтвет: ${finalText}'}
    ];
    try {
      return await usecase.complete(messages: messages, settings: _settings);
    } catch (_) {
      return '';
    }
  }

  // ===== Tools =====
  Future<Map<String, dynamic>> _callMcpSearch(Map<String, dynamic> args, {Duration? timeout}) async {
    final url = _settings.mcpServerUrl?.trim();
    if (!(_settings.useMcpServer && url != null && url.isNotEmpty)) {
      return {'warning': 'MCP выключен или не сконфигурирован'};
    }
    final client = McpClient();
    try {
      await client.connect(url);
      await client.initialize(timeout: const Duration(seconds: 3));
      final result = await client.toolsCall('yandex_search_web', {
        if (args.containsKey('queryText')) 'queryText': args['queryText'],
        if (args.containsKey('query')) 'query': args['query'],
      }, timeout: timeout ?? const Duration(seconds: 15));
      return {'result': result};
    } catch (e) {
      return {'error': e.toString()};
    } finally {
      await client.close();
    }
  }

  // Very small safe evaluator for simple expressions like 2+2*3, (1+2)/3.
  num _safeEval(String expr) {
    // This is intentionally simple: only digits, + - * / . and parentheses
    final cleaned = expr.replaceAll(RegExp(r'[^0-9+\-*/(). ]'), '');
    // No real parser here — just handle trivial cases to avoid bringing heavy deps.
    try {
      // As a minimal approach, split by + and - after computing * and / left-to-right
      final tokens = _tokenize(cleaned);
      return _compute(tokens);
    } catch (_) {
      return double.nan;
    }
  }

  List<String> _tokenize(String s) {
    final out = <String>[];
    final re = RegExp(r"(\d+\.?\d*|[+\-*/()])");
    for (final m in re.allMatches(s)) {
      out.add(m.group(0)!);
    }
    return out;
  }

  num _compute(List<String> t) {
    // Shunting-yard to RPN
    final out = <String>[];
    final ops = <String>[];
    int prec(String op) => (op == '+' || op == '-') ? 1 : (op == '*' || op == '/') ? 2 : 0;
    bool isOp(String x) => ['+', '-', '*', '/'].contains(x);
    for (final x in t) {
      if (isOp(x)) {
        while (ops.isNotEmpty && isOp(ops.last) && prec(ops.last) >= prec(x)) {
          out.add(ops.removeLast());
        }
        ops.add(x);
      } else if (x == '(') {
        ops.add(x);
      } else if (x == ')') {
        while (ops.isNotEmpty && ops.last != '(') {
          out.add(ops.removeLast());
        }
        if (ops.isNotEmpty && ops.last == '(') ops.removeLast();
      } else {
        out.add(x);
      }
    }
    while (ops.isNotEmpty) out.add(ops.removeLast());

    // Evaluate RPN
    final st = <num>[];
    for (final x in out) {
      if (isOp(x)) {
        final b = st.removeLast();
        final a = st.removeLast();
        switch (x) {
          case '+': st.add(a + b); break;
          case '-': st.add(a - b); break;
          case '*': st.add(a * b); break;
          case '/': st.add(b == 0 ? double.nan : a / b); break;
        }
      } else {
        st.add(num.parse(x));
      }
    }
    return st.isEmpty ? 0 : st.single;
  }

  // ===== JSON helpers =====
  Map<String, dynamic>? _tryParseJson(String? s) {
    if (s == null) return null;
    try { return (jsonDecode(s) as Map<String, dynamic>); } catch (_) {}
    return null;
  }

  String? _extractFencedJson(String s) {
    final re = RegExp(r"```(?:json)?\n([\s\S]*?)\n```", multiLine: true);
    final m = re.firstMatch(s);
    return m?.group(1)?.trim();
  }
}

class _Plan {
  final List<Map<String, dynamic>> steps;
  final List<String> tools;

  _Plan({required this.steps, required this.tools});

  factory _Plan.fromJson(Map<String, dynamic> j) {
    final steps = <Map<String, dynamic>>[];
    final tools = <String>[];
    final js = j['plan'];
    if (js is List) {
      for (final x in js) {
        if (x is Map<String, dynamic>) steps.add(x);
      }
    }
    final ts = j['tools'];
    if (ts is List) {
      for (final t in ts) {
        tools.add(t.toString());
      }
    }
    return _Plan(steps: steps, tools: tools);
  }

  Map<String, dynamic> toJson() => {'plan': steps, 'tools': tools};
}
