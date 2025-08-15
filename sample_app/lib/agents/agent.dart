import 'dart:async';

import 'package:sample_app/data/llm/deepseek_usecase.dart';
import 'package:sample_app/data/llm/yandexgpt_usecase.dart';
import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/mcp_integration_service.dart';

class AgentMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  AgentMessage({required this.role, required this.content});
}

class Agent {
  final _controller = StreamController<String>.broadcast();
  final List<AgentMessage> _history = [];
  AppSettings _settings;
  final McpIntegrationService _mcpIntegrationService;
  static const String stopSequence = '<END>';

  Agent({required AppSettings initialSettings})
      : _settings = initialSettings,
        _mcpIntegrationService = McpIntegrationService();

  Stream<String> get responses => _controller.stream;

  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  void clearHistory() {
    _history.clear();
  }

  // Подготовка системного промпта с учетом формата ответа
  String _buildSystemContent() {
    final uncertaintyPolicy = _settings.reasoningMode
        ? 'Политика уточнений (режим рассуждения): Прежде чем выдавать итоговый ответ, оцени неопределённость результата по шкале от 0 до 1. '
            'Если неопределённость > 0.1 — задай пользователю до 10 уточняющих вопросов (по важности), '
            'не выдавай финальный результат и не добавляй маркер окончания. '
            'Когда неопределённость ≤ 0.1 — сформируй итоговый результат и добавь маркер окончания $stopSequence. '
            'ПРИМЕЧАНИЕ: Маркер окончания предназначен для агента и будет скрыт от пользователя.'
        : 'Политика уточнений: Прежде чем выдавать итоговый ответ, оцени неопределённость результата по шкале от 0 до 1. '
            'Если неопределённость > 0.1 — задай пользователю 1–5 конкретных уточняющих вопросов (по важности), '
            'не выдавай финальный результат и не добавляй маркер окончания. '
            'Когда неопределённость ≤ 0.1 — сформируй итоговый результат, после чего добавь маркер окончания $stopSequence.';

    if (_settings.responseFormat == ResponseFormat.json) {
      final schema = _settings.customJsonSchema ?? '{"key":"value"}';
      final questionsRule = _settings.reasoningMode
          ? 'If uncertainty > 0.1, ask up to 10 clarifying questions (most important first) and do NOT output the final JSON yet, and do NOT append the stop token. '
          : 'If uncertainty > 0.1, ask the user 1–5 clarifying questions (most important first) and do NOT output the final JSON yet, and do NOT append the stop token. ';
      final endNote = _settings.reasoningMode
          ? 'Finish your output with the exact token: $stopSequence. NOTE: The stop token is for the agent and will be hidden from the user.'
          : 'Finish your output with the exact token: $stopSequence.';
      return 'You are a helpful assistant that returns data in JSON format. '
          'Before producing the final JSON, evaluate your uncertainty in the completeness and correctness of the required data on a scale from 0 to 1. '
          '$questionsRule'
          'Once uncertainty ≤ 0.1, return ONLY valid minified JSON strictly matching the following schema: '
          '$schema '
          'Do not add explanations or any text outside JSON. $endNote';
    }

    return '${_settings.systemPrompt}\n\n$uncertaintyPolicy';
  }

  LlmUseCase _resolveUseCase() {
    switch (_settings.selectedNetwork) {
      case NeuralNetwork.deepseek:
        return DeepSeekUseCase();
      case NeuralNetwork.yandexgpt:
        return YandexGptUseCase();
    }
  }

  Future<void> send(String userText) async {
    if (userText.trim().isEmpty) return;

    // Обновляем историю c учетом лимита
    final limit = _settings.historyDepth.clamp(0, 100);

    _history.add(AgentMessage(role: 'user', content: userText));
    if (_history.length > limit) {
      _history.removeRange(0, _history.length - limit);
    }

    // Обогащаем контекст через MCP сервис
    final enrichedContext = await _mcpIntegrationService.enrichContext(userText, _settings);
    
    // Формируем системный промпт с учетом MCP данных
    final baseSystem = _buildSystemContent();
    final system = _mcpIntegrationService.buildEnrichedSystemPrompt(baseSystem, enrichedContext);

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': system},
      for (final m in _history) {'role': m.role, 'content': m.content},
    ];

    try {
      final usecase = _resolveUseCase();
      final answer = await usecase.complete(messages: messages, settings: _settings);

      // Сохраняем ответ в историю и эмитим для подписчиков
      _history.add(AgentMessage(role: 'assistant', content: answer));
      if (_history.length > limit) {
        _history.removeRange(0, _history.length - limit);
      }

      _controller.add(answer);
    } catch (e) {
      _controller.addError(e);
    }
  }

  void dispose() {
    _controller.close();
  }
}
