import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sample_app/main.dart';

void main() {
  testWidgets('App should display chat screen', (WidgetTester tester) async {
    // Загружаем тестовые переменные окружения
    await dotenv.load(fileName: "assets/.env");
    
    // Создаем виджет приложения и обновляем экран
    await tester.pumpWidget(const MyApp());

    // Проверяем, что экран чата отображается
    expect(find.byType(ChatScreen), findsOneWidget);
    
    // Проверяем, что заголовок приложения отображается
    expect(find.byType(AppBar), findsOneWidget);
    
    // Проверяем наличие поля ввода текста
    expect(find.byType(TextField), findsOneWidget);
  });
}
