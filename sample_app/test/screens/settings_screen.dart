import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/screens/settings_screen.dart';

// Мок для навигации
class MockNavigatorObserver extends Mock implements NavigatorObserver {}

// Мок для Route
class MockRoute<T> extends Mock implements Route<T> {
  @override
  Future<T?> get popped => Future<T?>.value(null);
}

void main() {
  group('SettingsScreen', () {
    late AppSettings initialSettings;
    late ValueNotifier<AppSettings> settingsNotifier;
    
    setUp(() {
      initialSettings = const AppSettings();
      settingsNotifier = ValueNotifier<AppSettings>(initialSettings);
      
      // Настройка моков для mocktail
      registerFallbackValue(MockRoute<dynamic>());
    });

    testWidgets('should display initial settings', (WidgetTester tester) async {
      // Arrange
      final mockObserver = MockNavigatorObserver();
      
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initialSettings: initialSettings,
            onSettingsChanged: (_) {},
          ),
          navigatorObservers: [mockObserver],
        ),
      );

      // Assert
      expect(find.text('Настройки'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<NeuralNetwork>), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<ResponseFormat>), findsOneWidget);
      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.text('Текст'), findsOneWidget);
      expect(find.text('System prompt'), findsOneWidget);
      expect(find.byKey(const Key('system_prompt_field')), findsOneWidget);
      expect(find.byType(IconButton), findsNWidgets(2)); // Кнопки назад и сохранить
    });

    testWidgets('should update network selection', (WidgetTester tester) async {
      // Arrange
      final mockObserver = MockNavigatorObserver();
      AppSettings? savedSettings;
      
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initialSettings: initialSettings,
            onSettingsChanged: (settings) => savedSettings = settings,
          ),
          navigatorObservers: [mockObserver],
        ),
      );

      // Act - открываем выпадающий список
      await tester.tap(find.byType(DropdownButtonFormField<NeuralNetwork>));
      await tester.pumpAndSettle();
      
      // Выбираем YandexGPT
      await tester.tap(find.text('YandexGPT').last);
      await tester.pumpAndSettle();

      // Сохраняем настройки
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Assert
      expect(savedSettings, isNotNull);
      expect(savedSettings?.selectedNetwork, NeuralNetwork.yandexgpt);
      
      // Проверяем, что экран закрывается после сохранения
      verify(() => mockObserver.didPop(any(), any()));
    });

    testWidgets('should show JSON schema input when JSON format selected', 
        (WidgetTester tester) async {
      // Arrange
      final mockObserver = MockNavigatorObserver();
      
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initialSettings: initialSettings,
            onSettingsChanged: (_) {},
          ),
          navigatorObservers: [mockObserver],
        ),
      );

      // Act - меняем формат на JSON
      await tester.tap(find.byType(DropdownButtonFormField<ResponseFormat>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JSON схема').last);
      await tester.pumpAndSettle();

      // Assert - должно появиться поле для ввода JSON схемы
      expect(find.byKey(const Key('json_schema_field')), findsOneWidget);
      expect(find.text('JSON схема (опционально)'), findsOneWidget);
    });

    testWidgets('should save custom JSON schema', (WidgetTester tester) async {
      // Arrange
      final mockObserver = MockNavigatorObserver();
      AppSettings? savedSettings;
      const testSchema = '{"type": "object"}';
      
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initialSettings: initialSettings.copyWith(
              responseFormat: ResponseFormat.json,
            ),
            onSettingsChanged: (settings) => savedSettings = settings,
          ),
          navigatorObservers: [mockObserver],
        ),
      );

      // Act - вводим JSON схему
      await tester.enterText(find.byKey(const Key('json_schema_field')), testSchema);
      await tester.pump();
      
      // Сохраняем настройки
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Assert
      expect(savedSettings, isNotNull);
      expect(savedSettings?.customJsonSchema, testSchema);
      expect(savedSettings?.responseFormat, ResponseFormat.json);
      
      // Проверяем, что экран закрывается после сохранения
      verify(() => mockObserver.didPop(any(), any()));
    });

    testWidgets('should save system prompt', (WidgetTester tester) async {
      // Arrange
      final mockObserver = MockNavigatorObserver();
      AppSettings? savedSettings;
      const newPrompt = 'You are a super helpful assistant.';

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initialSettings: initialSettings,
            onSettingsChanged: (settings) => savedSettings = settings,
          ),
          navigatorObservers: [mockObserver],
        ),
      );

      // Act - изменяем system prompt
      await tester.enterText(find.byKey(const Key('system_prompt_field')), newPrompt);
      await tester.pump();

      // Сохраняем настройки
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Assert
      expect(savedSettings, isNotNull);
      expect(savedSettings!.systemPrompt, newPrompt);

      // Проверяем, что экран закрывается после сохранения
      verify(() => mockObserver.didPop(any(), any()));
    });
  });
}
