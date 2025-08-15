import 'package:sample_app/agents/agent.dart' show Agent; // for stopSequence
import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/data/llm/deepseek_usecase.dart';
import 'package:sample_app/data/llm/yandexgpt_usecase.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/mcp_integration_service.dart';

class ReasoningResult {
  final String text;
  final bool isFinal; // признак окончательного ответа

  const ReasoningResult({
    required this.text,
    required this.isFinal,
  });
}

extension on ReasoningAgent {
  // Пытаемся извлечь численное значение неопределённости из текста ответа.
  // Поддерживаются варианты на русском и английском, а также проценты.
  double? _extractUncertainty(String text) {
    final patterns = <RegExp>[
      // «Неопределённость: 0.4», «неопределенность = 0,25»
      RegExp(r'неопредел[её]нн?ость\s*[:=]?\s*([0-9]{1,3}(?:[\.,][0-9]{1,3})?)\s*%?', caseSensitive: false),
      // «Uncertainty: 0.4», «uncertainty = 25%»
      RegExp(r'uncertainty\s*[:=]?\s*([0-9]{1,3}(?:[\.,][0-9]{1,3})?)\s*%?', caseSensitive: false),
      // Процент отдельно: «40% неопределенности»
      RegExp(r'([0-9]{1,3})\s*%\s*(?:неопредел|uncertainty)', caseSensitive: false),
    ];

    for (final re in patterns) {
      final m = re.firstMatch(text);
      if (m != null) {
        var raw = m.group(1) ?? '';
        raw = raw.replaceAll(',', '.');
        final val = double.tryParse(raw);
        if (val == null) continue;
        // Если это похоже на проценты (>1), нормализуем
        final normalized = val > 1 ? val / 100.0 : val;
        if (normalized >= 0 && normalized <= 1) return normalized;
      }
    }
    return null;
  }
}

/// Рассуждающий агент с историей и политикой уточнений.
/// - Хранит историю общения
/// - Имеет метод очистки истории
/// - Возвращает ответ с признаком окончательности и окончания темы
/// - Если агент задаёт вопрос, не добавляет stopSequence и isFinal=false
class ReasoningAgent {
  static const String stopSequence = Agent.stopSequence;

  final List<_Msg> _history = [];
  AppSettings _settings;
  final String? extraSystemPrompt; // дополнительный системный промпт
  final McpIntegrationService _mcpIntegrationService;

  ReasoningAgent({AppSettings? baseSettings, this.extraSystemPrompt})
      : _settings = (baseSettings ?? const AppSettings()).copyWith(
          reasoningMode: true,
          // формат ответа оставляем согласно настройкам; по умолчанию пусть будет текст
        ),
        _mcpIntegrationService = McpIntegrationService();

  void updateSettings(AppSettings settings) {
    _settings = settings.copyWith(reasoningMode: true);
  }

  void clearHistory() => _history.clear();

  LlmUseCase _resolveUseCase() {
    switch (_settings.selectedNetwork) {
      case NeuralNetwork.deepseek:
        return DeepSeekUseCase();
      case NeuralNetwork.yandexgpt:
        return YandexGptUseCase();
    }
  }

  String _buildSystemContent() {
    final uncertaintyPolicy = 'Политика уточнений (режим рассуждения): Прежде чем выдавать итоговый ответ, '
        'оцени неопределённость результата по шкале от 0 до 1. '
        'Если неопределённость > 0.1 — задай пользователю уточняющий вопрос, не выдавай финальный результат и не добавляй маркер окончания. '
        'При этом в НЕКОНЕЧНОМ ответе выведи отдельной строкой: "Неопределённость: <значение>" (например: "Неопределённость: 0.27"). '
        'Когда неопределённость ≤ 0.1 — сформируй итоговый результат и добавь маркер окончания $stopSequence. '
        'В КОНЕЧНОМ ответе НЕ выводи строку с неопределённостью. '
        'ПРИМЕЧАНИЕ: Маркер окончания предназначен для агента и будет скрыт от пользователя. '
        'Не добавляй никаких других дополнений к ответам, кроме указанной строки про неопределённость в неоконечных ответах и маркера окончания в конечных.'
        'Если есть уточняющие вопросы не формулируй окончательный ответ и не добавляй маркер окончания.';

    if (_settings.responseFormat == ResponseFormat.json) {
      final schema = _settings.customJsonSchema ?? '{"key":"value"}';
      final questionsRule = 'If uncertainty > 0.1, ask up to 10 clarifying questions (most important first) and do NOT output the final JSON yet, and do NOT append the stop token. ';
      final endNote = 'Finish your output with the exact token: $stopSequence. NOTE: The stop token is for the agent and will be hidden from the user.';
      return 'You are a helpful assistant that returns data in JSON format. '
          'Before producing the final JSON, evaluate your uncertainty in the completeness and correctness of the required data on a scale from 0 to 1. '
          '$questionsRule'
          'Once uncertainty ≤ 0.1, return ONLY valid minified JSON strictly matching the following schema: '
          '$schema '
          'Do not add explanations or any text outside JSON. $endNote';
    }

    // Для обычного текста используем системный промпт из настроек, добавив политику уточнений и доп. промпт
    final extras = (extraSystemPrompt != null && extraSystemPrompt!.trim().isNotEmpty)
        ? '\n\n${extraSystemPrompt!.trim()}'
        : '';
    return '${_settings.systemPrompt}\n\n$uncertaintyPolicy$extras';
  }

  Future<Map<String, dynamic>> ask(String userText) async {
    if (userText.trim().isEmpty) {
      return {
        'result': const ReasoningResult(text: '', isFinal: false),
        'mcp_used': false,
      };
    }

    // обновляем историю в пределах лимита
    final limit = _settings.historyDepth.clamp(0, 100);
    _history.add(_Msg('user', userText));
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
      var answer = await usecase.complete(messages: messages, settings: _settings);

      // предварительно определяем финальность по наличию stopSequence
      var hasStop = answer.contains(stopSequence);
      if (hasStop) {
        answer = answer.replaceAll(stopSequence, '').trim();
      }

      // Парсим неопределённость; если > 0.1 — ответ не финальный, даже если маркер присутствовал
      final parsedUncertainty = _extractUncertainty(answer);
      if (parsedUncertainty != null && parsedUncertainty > 0.1) {
        hasStop = false; // принудительно снимаем финальность
      }

      // сохраняем ответ ассистента в историю
      _history.add(_Msg('assistant', answer));
      if (_history.length > limit) {
        _history.removeRange(0, _history.length - limit);
      }

      return {
        'result': ReasoningResult(
          text: answer,
          isFinal: hasStop,
        ),
        'mcp_used': enrichedContext['mcp_used'] ?? false,
      };
    } catch (e) {
      // В случае ошибки не меняем историю и возвращаем сообщение ошибки как текст
      return {
        'result': ReasoningResult(
          text: 'Ошибка: $e',
          isFinal: true,
        ),
        'mcp_used': false,
      };
    }
  }
}

class _Msg {
  final String role; // 'user' | 'assistant'
  final String content;
  _Msg(this.role, this.content);
}
