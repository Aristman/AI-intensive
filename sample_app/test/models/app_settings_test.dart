import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('should have correct default values', () {
      final settings = AppSettings();
      
      expect(settings.selectedNetwork, NeuralNetwork.deepseek);
      expect(settings.responseFormat, ResponseFormat.text);
      expect(settings.customJsonSchema, isNull);
    });

    test('should create a copy with updated values', () {
      const customSchema = '{"type": "object"}';
      final settings = AppSettings();
      
      final updated = settings.copyWith(
        selectedNetwork: NeuralNetwork.yandexgpt,
        responseFormat: ResponseFormat.json,
        customJsonSchema: customSchema,
      );
      
      expect(updated.selectedNetwork, NeuralNetwork.yandexgpt);
      expect(updated.responseFormat, ResponseFormat.json);
      expect(updated.customJsonSchema, customSchema);
    });

    test('should convert to and from JSON', () {
      const customSchema = '{"type": "object"}';
      final settings = AppSettings(
        selectedNetwork: NeuralNetwork.yandexgpt,
        responseFormat: ResponseFormat.json,
        customJsonSchema: customSchema,
      );
      
      // Проверяем, что toJson не падает
      expect(() => settings.toJson(), returnsNormally);
      
      // Проверяем, что fromJson не падает
      final json = {
        'selectedNetwork': 'yandexgpt',
        'responseFormat': 'json',
        'customJsonSchema': customSchema,
      };
      expect(() => AppSettings.fromJson(json), returnsNormally);
    });

    test('should return correct network name', () {
      expect(
        const AppSettings(selectedNetwork: NeuralNetwork.deepseek).selectedNetworkName,
        'DeepSeek',
      );
      
      expect(
        const AppSettings(selectedNetwork: NeuralNetwork.yandexgpt).selectedNetworkName,
        'YandexGPT',
      );
    });

    test('should return correct format name', () {
      expect(
        const AppSettings(responseFormat: ResponseFormat.text).responseFormatName,
        'Text',
      );
      
      expect(
        const AppSettings(responseFormat: ResponseFormat.json).responseFormatName,
        'JSON',
      );
    });
  });
}
