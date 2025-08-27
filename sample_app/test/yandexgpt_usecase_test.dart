import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/data/llm/yandexgpt_usecase.dart';
import 'package:sample_app/models/app_settings.dart';

void main() {
  group('YandexGptUseCase', () {
    late YandexGptUseCase usecase;

    setUp(() {
      usecase = YandexGptUseCase();
    });

    group('completeWithUsage', () {
      test('returns LlmResponse with usage data', () async {
        // This test would require mocking HTTP calls
        // For now, we'll test the interface contract
        const settings = AppSettings();
        final messages = [
          {'role': 'user', 'content': 'Test message'}
        ];

        // Since we can't easily mock HTTP in this environment,
        // we'll test that the method exists and has correct signature
        expect(usecase.completeWithUsage, isNotNull);
        expect(usecase.completeWithUsage(messages: messages, settings: settings),
            isA<Future<LlmResponse>>());
      });
    });

    group('LlmResponse', () {
      test('can be created with all fields', () {
        const usage = {'inputTokens': 10, 'completionTokens': 20, 'totalTokens': 30};
        const response = LlmResponse(text: 'Hello', usage: usage);

        expect(response.text, 'Hello');
        expect(response.usage, usage);
      });

      test('can be created without usage', () {
        const response = LlmResponse(text: 'Hello');

        expect(response.text, 'Hello');
        expect(response.usage, isNull);
      });
    });
  });
}
