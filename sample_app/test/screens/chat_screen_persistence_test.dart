import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sample_app/screens/chat_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ChatScreen reasoning persists history across rebuild', (tester) async {
    // 1) Стартуем экран в reasoning-режиме
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatScreen(reasoningOverride: true),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 2) Отправляем сообщение
    const String userText = 'Привет';
    await tester.enterText(find.byType(TextField), userText);

    // Нажимаем кнопку отправки
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    // 3) Убеждаемся, что пользовательское сообщение отображается
    expect(find.text(userText), findsWidgets);

    // 4) Перезапускаем виджет (новый экземпляр)
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatScreen(reasoningOverride: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 5) История должна восстановиться (как минимум пользовательское сообщение)
    expect(find.text(userText), findsWidgets);
  });

  testWidgets('ChatScreen reasoning clear history button clears and persists', (tester) async {
    // Стартуем и отправляем сообщение
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatScreen(reasoningOverride: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const String userText = 'Очисти меня';
    await tester.enterText(find.byType(TextField), userText);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text(userText), findsWidgets);

    // Нажимаем кнопку очистки истории
    final clearBtn = find.byKey(const Key('clear_history_button'));
    expect(clearBtn, findsOneWidget);
    await tester.tap(clearBtn);
    await tester.pumpAndSettle();

    // Сообщений не должно остаться
    expect(find.text(userText), findsNothing);

    // Перезапуск виджета: история должна остаться пустой
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatScreen(reasoningOverride: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(userText), findsNothing);
  });
}
