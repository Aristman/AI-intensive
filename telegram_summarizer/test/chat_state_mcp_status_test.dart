import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telegram_summarizer/state/chat_state.dart';
import 'package:telegram_summarizer/data/mcp/mcp_client.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';

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

  _FakeMcp(this.url);

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
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

void main() {
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
}
