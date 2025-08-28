import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telegram_summarizer/state/chat_state.dart';
import 'package:telegram_summarizer/data/mcp/mcp_client.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  }) async {
    return 'ok';
  }
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

  // Unused in this test
  @override
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params, {Duration timeout = const Duration(seconds: 20)}) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> summarize(String text, {Duration timeout = const Duration(seconds: 20)}) {
    throw UnimplementedError();
  }
}

class _SlowFailMcp implements McpClient {
  @override
  final String url;
  bool _connected = false;
  final Duration delay;
  @override
  void Function()? onStateChanged;
  @override
  void Function(Object error)? onErrorCallback;

  _SlowFailMcp(this.url, {this.delay = const Duration(milliseconds: 50)});

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    await Future.delayed(delay);
    final err = Exception('fail connect');
    onErrorCallback?.call(err);
    throw err;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params, {Duration timeout = const Duration(seconds: 20)}) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> summarize(String text, {Duration timeout = const Duration(seconds: 20)}) {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  test('ChatState exposes MCP connection status and can reconnect', () async {
    final chat = ChatState(_FakeLlm(), _FakeMcp('ws://test'));

    expect(chat.hasMcp, isTrue);
    expect(chat.mcpConnected, isFalse);

    await chat.connectMcp();
    expect(chat.mcpConnected, isTrue);

    await chat.disconnectMcp();
    expect(chat.mcpConnected, isFalse);

    await chat.reconnectMcp();
    expect(chat.mcpConnected, isTrue);
  });

  test('ChatState shows connecting and captures error on failed reconnect', () async {
    final chat = ChatState(_FakeLlm(), _SlowFailMcp('ws://bad'));

    // Start reconnect and verify transient connecting state flips
    final future = chat.reconnectMcp();
    // Immediately after call, connecting should be true
    expect(chat.mcpConnecting, isTrue);
    await future;
    expect(chat.mcpConnecting, isFalse);
    expect(chat.mcpConnected, isFalse);
    expect(chat.mcpError, isNotNull);
  });

  test('ChatState.connectMcp is invoked during load when MCP is present', () async {
    final chat = ChatState(_FakeLlm(), _FakeMcp('ws://test'));
    await chat.load();
    expect(chat.mcpConnected, isTrue);
  });
}
