import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/screens/settings_screen.dart';
import 'package:sample_app/services/settings_service.dart';

// Мок для SettingsService
class MockSettingsService extends Mock implements SettingsService {}

// Фейковый класс для Route
class FakeRoute<T> extends Fake implements Route<T> {
  @override
  RouteSettings get settings => const RouteSettings();
  
  @override
  bool get isCurrent => false;
  
  @override
  bool get isActive => true;
  
  @override
  bool get isFirst => false;
  
  @override
  T? get currentResult => null;
}

void main() {
  // Регистрируем фейковые значения для mocktail
  setUpAll(() {
    registerFallbackValue(FakeRoute<dynamic>());
    registerFallbackValue(const AppSettings());
  });

  group('SettingsScreen', () {
    late AppSettings initialSettings;
    late MockNavigatorObserver mockObserver;
    late MockSettingsService mockSettingsService;
    
    setUp(() {
      initialSettings = const AppSettings();
      mockObserver = MockNavigatorObserver();
      mockSettingsService = MockSettingsService();
      
      // Настройка моков для навигации
      when(() => mockObserver.didPush(any(), any())).thenAnswer((_) {});
      when(() => mockObserver.didPop(any(), any())).thenAnswer((_) {});
      
      // Настройка мока для SettingsService
      when(() => mockSettingsService.saveSettings(any())).thenAnswer((_) async => true);
    });

    testWidgets('should display initial settings', (WidgetTester tester) async {
      // Arrange & Act
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
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<NeuralNetwork>), findsOneWidget);
      expect(find.text('DeepSeek'), findsOneWidget);
    });

    testWidgets('should update network selection', (WidgetTester tester) async {
      // Arrange
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
    });

    testWidgets('should show JSON schema input when JSON format selected', 
        (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initialSettings: initialSettings.copyWith(
              responseFormat: ResponseFormat.json,
            ),
            onSettingsChanged: (_) {},
          ),
          navigatorObservers: [mockObserver],
        ),
      );

      // Assert - должно быть поле для ввода JSON схемы
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('should save custom JSON schema', (WidgetTester tester) async {
      // Arrange
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
      await tester.enterText(find.byType(TextField), testSchema);
      await tester.pump();
      
      // Сохраняем настройки
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Assert
      expect(savedSettings, isNotNull);
      expect(savedSettings?.customJsonSchema, testSchema);
      expect(savedSettings?.responseFormat, ResponseFormat.json);
    });
  });
}

// Мок для навигации
class MockNavigatorObserver extends Mock implements NavigatorObserver {}
