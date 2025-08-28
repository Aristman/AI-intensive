// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:telegram_summarizer/main.dart';

void main() {
  testWidgets('ChatScreen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // AppBar title
    expect(find.text('Telegram Summarizer'), findsOneWidget);

    // Input and send button present
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
    expect(find.byKey(const Key('send_button')), findsOneWidget);

    // Type and send a message
    await tester.enterText(find.byKey(const Key('chat_input')), 'Привет');
    await tester.tap(find.byKey(const Key('send_button')));
    await tester.pump();

    // Expect user and placeholder LLM reply
    expect(find.textContaining('Привет'), findsWidgets);
    expect(find.textContaining('Ответ будет позже'), findsOneWidget);
  });
}
