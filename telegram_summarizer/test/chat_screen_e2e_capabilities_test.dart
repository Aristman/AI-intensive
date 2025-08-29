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

class _RecordingLlm implements LlmUseCase {
  List<Map<String, String>>? lastMessages;
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
    lastMessages = List<Map<String, String>>.from(messages);
    return 'LLM ok';
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

  testWidgets('E2E: MCP capabilities are added to LLM prompt and structuredContent is rendered', (tester) async {
    final llm = _RecordingLlm();
    final mcp = _CapableMcp('ws://test');
    final chat = ChatState(llm, mcp);
    final settings = _FakeSettings();

    await tester.pumpWidget(_wrap(chat: chat, settings: settings));

    // Подключаем MCP через UI
    final reconnectBtn = find.byTooltip('Переподключить MCP');
    expect(reconnectBtn, findsOneWidget);
    await tester.tap(reconnectBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // дождаться завершения подключения (минимальная задержка)

    // Отправляем сообщение
    await tester.enterText(find.byKey(const Key('chat_input')), 'Привет');
    await tester.tap(find.byKey(const Key('send_button')));

    await tester.pumpAndSettle();

    // Проверяем, что LLM получил системное сообщение с capabilities
    final messages = llm.lastMessages;
    expect(messages, isNotNull);
    final hasCaps = messages!.any((m) => m['role'] == 'system' && (m['content']?.contains('Capabilities:') ?? false));
    expect(hasCaps, isTrue);

    // Проверяем, что отрисована SummaryCard из structuredContent
    expect(find.byType(SummaryCard), findsWidgets);
  });
}
