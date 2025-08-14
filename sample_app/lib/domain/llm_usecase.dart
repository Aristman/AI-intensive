import 'package:sample_app/models/app_settings.dart';

/// Абстракция юзкейса LLM. Позволяет подменять провайдера.
abstract class LlmUseCase {
  /// Выполняет completion на основе истории и настроек.
  /// Возвращает текст ответа ассистента.
  Future<String> complete({
    required List<Map<String, String>> messages,
    required AppSettings settings,
  });
}
