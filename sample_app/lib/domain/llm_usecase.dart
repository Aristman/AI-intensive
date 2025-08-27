import 'package:sample_app/models/app_settings.dart';

/// Абстракция юзкейса LLM. Позволяет подменять провайдера.
abstract class LlmUseCase {
  /// Выполняет completion на основе истории и настроек.
  /// Возвращает текст ответа ассистента.
  Future<String> complete({
    required List<Map<String, String>> messages,
    required AppSettings settings,
  });

  /// Выполняет completion с возвратом информации о токенах.
  /// Возвращает LlmResponse с текстом и usage.
  Future<LlmResponse> completeWithUsage({
    required List<Map<String, String>> messages,
    required AppSettings settings,
  });
}

/// Класс для ответа от LLM с текстом и информацией об использовании токенов.
class LlmResponse {
  final String text;
  final Map<String, int>? usage; // {'inputTokens': 100, 'completionTokens': 50, 'totalTokens': 150}

  const LlmResponse({
    required this.text,
    this.usage,
  });
}
