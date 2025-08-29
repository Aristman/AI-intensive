import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_summarizer/state/chat_state.dart';
import 'package:telegram_summarizer/state/settings_state.dart';
import 'package:telegram_summarizer/ui/chat_screen.dart';
import 'package:telegram_summarizer/data/mcp/mcp_client.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:http/http.dart' as http;
import 'package:telegram_summarizer/widgets/summary_card.dart';

class _FakeSettings extends SettingsState {
  @override
  String get llmModel => 'fake-model';
  @override
  String get mcpUrl => 'ws://test';
  @override
  String get iamToken => '';
  @override
  String get apiKey => '';
  @override
  String get folderId => '';
}

class _ConditionalLlm implements LlmUseCase {
  @override
  Future<String> complete({
    required List<Map<String, String>> messages,
    required String modelUri,
    required String iamToken,
    required String apiKey,
    required String folderId,
    double temperature = 0.2,
    int maxTokens = 128,
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async {
    final hasCaps = messages.any((m) => m['role'] == 'system' && (m['content']?.contains('Capabilities:') ?? false));
    return hasCaps ? 'WITH_CAPS_RESPONSE' : 'NO_CAPS_RESPONSE';
  }
}

class _CapableMcp implements McpClient {
  @override
  final String url;
  bool _connected = false;
  @override
  void Function()? onStateChanged;
  @override
  void Function(Object error)? onErrorCallback;
  _CapableMcp(this.url);
  @override
  bool get isConnected => _connected;
  @override
  Future<void> connect() async {
    _connected = true;
    onStateChanged?.call();
  }
  @override
  Future<void> disconnect() async {
    _connected = false;
    onStateChanged?.call();
  }
  @override
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params, {Duration timeout = const Duration(seconds: 20)}) async {
    if (method == 'capabilities') {
      return <String, dynamic>{'tools': ['tg.resolve', 'tg.fetch']};
    }
    return <String, dynamic>{};
  }
  @override
  Future<Map<String, dynamic>> summarize(String text, {Duration timeout = const Duration(seconds: 20)}) async {
    return <String, dynamic>{'summary': 'ok', 'items': []};
  }
}

Widget _wrap({required ChatState chat, required SettingsState settings}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChatState>.value(value: chat),
      ChangeNotifierProvider<SettingsState>.value(value: settings),
    ],
    child: const MaterialApp(home: ChatScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('LLM ответ отличается при наличии capabilities: без MCP', (tester) async {
    final llm = _ConditionalLlm();
    final chat = ChatState(llm, null); // MCP отсутствует
    final settings = _FakeSettings();

    await tester.pumpWidget(_wrap(chat: chat, settings: settings));

    await tester.enterText(find.byKey(const Key('chat_input')), 'Запрос');
    await tester.tap(find.byKey(const Key('send_button')));
    await tester.pumpAndSettle();

    // Ответ без capabilities
    expect(find.text('NO_CAPS_RESPONSE'), findsOneWidget);
    // Нет структурированного контента
    expect(find.byType(SummaryCard), findsNothing);
  });

  testWidgets('LLM ответ отличается при наличии capabilities: с MCP и списком инструментов в тултипе', (tester) async {
    final llm = _ConditionalLlm();
    final mcp = _CapableMcp('ws://test');
    final chat = ChatState(llm, mcp);
    final settings = _FakeSettings();

    await tester.pumpWidget(_wrap(chat: chat, settings: settings));

    // Подключаем MCP, чтобы подтянуть capabilities
    final reconnectBtn = find.byTooltip('Переподключить MCP');
    expect(reconnectBtn, findsOneWidget);
    await tester.tap(reconnectBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Проверим тултип на индикаторе MCP
    final indicatorTooltipFinder = find.byWidgetPredicate(
      (w) => w is Tooltip && (w.message).toString().contains('MCP подключен'),
    );
    expect(indicatorTooltipFinder, findsOneWidget);
    final tooltip = tester.widget<Tooltip>(indicatorTooltipFinder);
    expect(tooltip.message, contains('Инструменты: tg.resolve, tg.fetch'));

    // Отправляем сообщение
    await tester.enterText(find.byKey(const Key('chat_input')), 'Запрос');
    await tester.tap(find.byKey(const Key('send_button')));
    await tester.pumpAndSettle();

    // Ответ с capabilities
    expect(find.text('WITH_CAPS_RESPONSE'), findsOneWidget);
    // Структурированный контент присутствует
    expect(find.byType(SummaryCard), findsWidgets);
  });
}
