import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sample_app/main.dart';

void main() {
  // Настройка тестового окружения
  setUpAll(() async {
    // Загружаем тестовые переменные окружения
    await dotenv.load(fileName: "assets/.env");
  });

  testWidgets('ChatScreen should display initial UI', (WidgetTester tester) async {
    // Создаем виджет приложения и обновляем экран
    await tester.pumpWidget(const MaterialApp(
      home: ChatScreen(),
    ));

    // Проверяем, что поле ввода отображается
    expect(find.byType(TextField), findsOneWidget);
    
    // Проверяем, что кнопка отправки отображается
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets('ChatScreen should show error when sending message without API key',
      (WidgetTester tester) async {
    // Создаем тестовый случай, когда API ключ отсутствует
    await dotenv.env.remove('DEEPSEEK_API_KEY');
    
    // Создаем виджет приложения и обновляем экран
    await tester.pumpWidget(const MaterialApp(
      home: ChatScreen(),
    ));

    // Находим поле ввода и вводим текст
    final textField = find.byType(TextField);
    await tester.enterText(textField, 'Тестовое сообщение');
    
    // Нажимаем кнопку отправки
    await tester.tap(find.byIcon(Icons.send));
    
    // Обновляем виджет после изменения состояния
    await tester.pump();
    
    // Проверяем, что отображается сообщение об ошибке
    final errorFinder = find.textContaining('Ошибка: API ключ не найден', findRichText: true);
    expect(errorFinder, findsOneWidget);
  });
}
