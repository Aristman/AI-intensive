import 'dart:async';

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
    // MVP: имитация короткого пайплайна анализа без реальных правок
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

      await Future<void>.delayed(const Duration(milliseconds: 100));

      ctrl.add(AgentEvent(
        id: 'e2',
        runId: runId,
        stage: AgentStage.analysis_result,
        message: 'Анализ завершён, найдено 0 проблем (заглушка)',
        progress: 0.7,
        meta: {
          'issues': <Map<String, dynamic>>[],
        },
      ));

      await Future<void>.delayed(const Duration(milliseconds: 100));

      ctrl.add(AgentEvent(
        id: 'e3',
        runId: runId,
        stage: AgentStage.pipeline_complete,
        message: 'Готово',
        progress: 1.0,
        meta: {
          'patches': <Map<String, dynamic>>[],
          'summary': 'Нет изменений (MVP заглушка)',
        },
      ));
      await ctrl.close();
    });

    return ctrl.stream;
  }

  @override
  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  @override
  void dispose() {}
}
