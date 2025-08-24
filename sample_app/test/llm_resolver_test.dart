import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/domain/llm_resolver.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/data/llm/deepseek_usecase.dart';
import 'package:sample_app/data/llm/yandexgpt_usecase.dart';

void main() {
  group('resolveLlmUseCase', () {
    test('returns DeepSeekUseCase when selectedNetwork is deepseek', () {
      const settings = AppSettings(selectedNetwork: NeuralNetwork.deepseek);
      final usecase = resolveLlmUseCase(settings);
      expect(usecase, isA<DeepSeekUseCase>());
    });

    test('returns YandexGptUseCase when selectedNetwork is yandexgpt', () {
      const settings = AppSettings(selectedNetwork: NeuralNetwork.yandexgpt);
      final usecase = resolveLlmUseCase(settings);
      expect(usecase, isA<YandexGptUseCase>());
    });
  });
}
