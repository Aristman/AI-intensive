import 'package:sample_app/domain/llm_resolver.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/mcp_integration_service.dart';

/// Простой агент-консультант.
/// - Имеет базовый системный промпт для общих консультаций
/// - Можно переопределить системный промпт при инициализации
/// - Не хранит историю диалога
/// - Возвращает ответ в виде простой строки
class SimpleAgent {
  static const String defaultSystemPrompt =
      'Ты вежливый и лаконичный консультант, отвечающий на общие вопросы пользователя. '
      'Давай чёткие и понятные ответы. Если чего-то не знаешь — скажи об этом честно.';

  final AppSettings _settings;
  final McpIntegrationService _mcpIntegrationService;

  SimpleAgent({AppSettings? baseSettings, String? systemPrompt})
      : _settings = (baseSettings ?? const AppSettings()).copyWith(
          reasoningMode: false,
          responseFormat: ResponseFormat.text,
          systemPrompt: systemPrompt ?? defaultSystemPrompt,
        ),
        _mcpIntegrationService = McpIntegrationService();

  /// Выполнить запрос к модели без сохранения истории
  Future<Map<String, dynamic>> ask(String userText) async {
    if (userText.trim().isEmpty) return {'answer': '', 'mcp_used': false};

    // Обогащаем контекст через MCP сервис
    final enrichedContext = await _mcpIntegrationService.enrichContext(userText, _settings);
    
    // Формируем системный промпт с учетом MCP данных
    final systemPrompt = _mcpIntegrationService.buildEnrichedSystemPrompt(
      _settings.systemPrompt,
      enrichedContext
    );

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userText},
    ];

    final usecase = resolveLlmUseCase(_settings);
    final answer = await usecase.complete(messages: messages, settings: _settings);
    
    return {
      'answer': answer,
      'mcp_used': enrichedContext['mcp_used'] ?? false,
    };
  }
}
