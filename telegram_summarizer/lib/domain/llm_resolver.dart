import 'package:telegram_summarizer/state/settings_state.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:telegram_summarizer/data/llm/yandex_gpt_usecase.dart';

/// Резолвер для выбора конкретной реализации LLM по настройкам приложения.
/// На текущем этапе всегда возвращает YandexGptUseCase, но оставлен как 
/// точка расширения для будущих LLM.
LlmUseCase resolveLlmUseCase(SettingsState settings) {
  final model = settings.llmModel.toLowerCase();
  // Будущая логика может выбирать разные реализации в зависимости от модели.
  if (model.contains('yandex')) {
    return YandexGptUseCase();
  }
  // По умолчанию — YandexGPT
  return YandexGptUseCase();
}
