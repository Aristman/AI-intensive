import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';

void main() {
  late SettingsService settingsService;
  
  setUp(() {
    // Используем реальный SharedPreferences с тестовыми данными
    SharedPreferences.setMockInitialValues({});
    settingsService = SettingsService();
  });

  group('SettingsService', () {
    test('should return default settings when no settings saved', () async {
      // Act
      final settings = await settingsService.getSettings();
      
      // Assert
      expect(settings.selectedNetwork, NeuralNetwork.deepseek);
      expect(settings.responseFormat, ResponseFormat.text);
      expect(settings.customJsonSchema, isNull);
    });

    test('should save and load settings correctly', () async {
      // Arrange
      final testSettings = AppSettings(
        selectedNetwork: NeuralNetwork.yandexgpt,
        responseFormat: ResponseFormat.json,
        customJsonSchema: '{"type": "object"}',
      );
      
      // Act - сохраняем настройки
      final saveResult = await settingsService.saveSettings(testSettings);
      
      // Assert - проверяем, что сохранение прошло успешно
      expect(saveResult, isTrue);
      
      // Act - загружаем настройки
      final loadedSettings = await settingsService.getSettings();
      
      // Assert - проверяем, что загруженные настройки соответствуют ожидаемым
      expect(loadedSettings.selectedNetwork, NeuralNetwork.yandexgpt);
      expect(loadedSettings.responseFormat, ResponseFormat.json);
      expect(loadedSettings.customJsonSchema, '{"type": "object"}');
    });

    test('should handle JSON parsing errors gracefully', () async {
      // Arrange - сохраняем невалидные JSON данные напрямую в SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_settings', '{invalid_json}');
      
      // Act
      final settings = await settingsService.getSettings();
      
      // Assert - должны вернуться настройки по умолчанию при ошибке парсинга
      expect(settings.selectedNetwork, NeuralNetwork.deepseek);
      expect(settings.responseFormat, ResponseFormat.text);
      expect(settings.customJsonSchema, isNull);
    });
  });
}
