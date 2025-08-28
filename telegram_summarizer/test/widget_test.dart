// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:telegram_summarizer/main.dart';
import 'package:telegram_summarizer/state/chat_state.dart';
import 'package:telegram_summarizer/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Fake LLM that returns a deterministic reply
class _FakeLlm implements LlmUseCase {
  @override
  Future<String> complete({
    required List<Map<String, String>> messages,
    required String modelUri,
    required String iamToken,
    required String apiKey,
    required String folderId,
    double temperature = 0.2,
    int maxTokens = 128,
    client,
  }) async => 'MOCK';
}

void main() {
  testWidgets('ChatScreen smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsState();
    await settings.load();
    final chat = ChatState(_FakeLlm());
    await chat.load();

    await tester.pumpWidget(MyApp(settings: settings, chat: chat));

    // AppBar title
    expect(find.text('Telegram Summarizer'), findsOneWidget);

    // Input and send button present
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
    expect(find.byKey(const Key('send_button')), findsOneWidget);

    // Type and send a message
    await tester.enterText(find.byKey(const Key('chat_input')), 'Привет');
    await tester.tap(find.byKey(const Key('send_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send_button')));
    await tester.pumpAndSettle();

    // Expect user and mock LLM reply
    expect(find.textContaining('Привет'), findsWidgets);
    expect(find.textContaining('MOCK'), findsOneWidget);
  });
}
