import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/data/llm/deepseek_usecase.dart';
import 'package:sample_app/data/llm/yandexgpt_usecase.dart';
import 'package:sample_app/data/llm/tinylama_usecase.dart';

/// Shared resolver that selects concrete LLM use case implementation
/// based on selected neural network in AppSettings.
LlmUseCase resolveLlmUseCase(AppSettings settings) {
  switch (settings.selectedNetwork) {
    case NeuralNetwork.deepseek:
      return DeepSeekUseCase();
    case NeuralNetwork.yandexgpt:
      return YandexGptUseCase();
    case NeuralNetwork.tinylama:
      return TinyLlamaUseCase();
  }
}
