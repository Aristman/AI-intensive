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

class _FakeSettings extends SettingsState {
  @override
  String get llmModel => 'fake-model';
  @override
  String get mcpUrl => 'ws://test';
}

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
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async => 'ok';
}

class _FakeMcp implements McpClient {
  @override
  final String url;
  bool _connected = false;
  @override
  void Function()? onStateChanged;
  @override
  void Function(Object error)? onErrorCallback;
  _FakeMcp(this.url);
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
    if (method == 'capabilities') return <String, dynamic>{};
    return <String, dynamic>{};
  }
  @override
  Future<Map<String, dynamic>> summarize(String text, {Duration timeout = const Duration(seconds: 20)}) async {
    return <String, dynamic>{};
  }
}

class _SlowFailMcp implements McpClient {
  @override
  final String url;
  bool _connected = false;
  @override
  void Function()? onStateChanged;
  @override
  void Function(Object error)? onErrorCallback;
  _SlowFailMcp(this.url);
  @override
  bool get isConnected => _connected;
  @override
  Future<void> connect() async {
    // имитируем задержку и ошибку
    await Future.delayed(const Duration(milliseconds: 50));
    final err = Exception('fail connect');
    onErrorCallback?.call(err);
    throw err;
  }
  @override
  Future<void> disconnect() async {
    _connected = false;
    onStateChanged?.call();
  }
  @override
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params, {Duration timeout = const Duration(seconds: 20)}) async {
    return <String, dynamic>{};
  }
  @override
  Future<Map<String, dynamic>> summarize(String text, {Duration timeout = const Duration(seconds: 20)}) async {
    return <String, dynamic>{};
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

  testWidgets('MCP indicator reflects states and reconnect to success', (tester) async {
    final chat = ChatState(_FakeLlm(), _FakeMcp('ws://test'));
    final settings = _FakeSettings();

    await tester.pumpWidget(_wrap(chat: chat, settings: settings));

    // hasMcp=true -> индикатор присутствует и красный (отключен)
    final statusIconFinder = find.byIcon(Icons.circle);
    expect(statusIconFinder, findsOneWidget);
    Icon statusIcon = tester.widget(statusIconFinder);
    expect(statusIcon.color, Colors.red);

    // Нажать "Переподключить MCP" -> connecting (amber), затем green
    final reconnectBtn = find.byTooltip('Переподключить MCP');
    expect(reconnectBtn, findsOneWidget);
    await tester.tap(reconnectBtn);
    await tester.pump(); // connecting frame
    statusIcon = tester.widget(statusIconFinder);
    expect(statusIcon.color, Colors.amber);

    await tester.pump(const Duration(milliseconds: 350)); // больше минимальной задержки
    statusIcon = tester.widget(statusIconFinder);
    expect(statusIcon.color, Colors.green);
  });

  testWidgets('Reconnect failure shows red indicator and error SnackBar', (tester) async {
    final chat = ChatState(_FakeLlm(), _SlowFailMcp('ws://bad'));
    final settings = _FakeSettings();

    await tester.pumpWidget(_wrap(chat: chat, settings: settings));

    final statusIconFinder = find.byIcon(Icons.circle);
    expect(statusIconFinder, findsOneWidget);

    final reconnectBtn = find.byTooltip('Переподключить MCP');
    await tester.tap(reconnectBtn);
    await tester.pump(); // connecting
    Icon statusIcon = tester.widget(statusIconFinder);
    expect(statusIcon.color, Colors.amber);

    await tester.pumpAndSettle(); // завершение с ошибкой

    statusIcon = tester.widget(statusIconFinder);
    expect(statusIcon.color, Colors.red);

    // SnackBar с ошибкой
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Не удалось подключиться к MCP'), findsOneWidget);
  });
}
