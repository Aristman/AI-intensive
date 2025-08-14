import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/data/llm/deepseek_usecase.dart';
import 'package:sample_app/data/llm/yandexgpt_usecase.dart';
import 'package:sample_app/models/app_settings.dart';

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

  SimpleAgent({AppSettings? baseSettings, String? systemPrompt})
      : _settings = (baseSettings ?? const AppSettings()).copyWith(
          reasoningMode: false,
          responseFormat: ResponseFormat.text,
          systemPrompt: systemPrompt ?? defaultSystemPrompt,
        );

  LlmUseCase _resolveUseCase() {
    switch (_settings.selectedNetwork) {
      case NeuralNetwork.deepseek:
        return DeepSeekUseCase();
      case NeuralNetwork.yandexgpt:
        return YandexGptUseCase();
    }
  }

  /// Выполнить запрос к модели без сохранения истории
  Future<String> ask(String userText) async {
    if (userText.trim().isEmpty) return '';

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _settings.systemPrompt},
      {'role': 'user', 'content': userText},
    ];

    final usecase = _resolveUseCase();
    final answer = await usecase.complete(messages: messages, settings: _settings);
    return answer;
  }
}
