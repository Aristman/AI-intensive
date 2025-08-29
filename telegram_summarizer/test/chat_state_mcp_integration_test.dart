import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:telegram_summarizer/data/mcp/mcp_client.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:telegram_summarizer/state/chat_state.dart';
import 'package:telegram_summarizer/state/settings_state.dart';

class FakeLlmUseCase implements LlmUseCase {
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
    Duration timeout = const Duration(seconds: 20),
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async {
    return 'LLM reply';
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ChatState attaches structuredContent from MCP on success', () async {
    late StreamChannelController<dynamic> ctrl;
    final mcp = McpClient(
      url: 'ws://test',
      connector: (uri) async {
        ctrl = StreamChannelController<dynamic>();
        // Handle capabilities and summarize
        ctrl.foreign.stream.listen((data) {
          final map = jsonDecode(data as String) as Map<String, dynamic>;
          final id = map['id'];
          final method = map['method'] as String?;
          if (method == 'capabilities') {
            ctrl.foreign.sink.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'tools': ['summarize']},
            }));
          } else {
            ctrl.foreign.sink.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'summary': 'ok',
                'source': 'mcp',
              },
            }));
          }
        });
        return ctrl.local;
      },
    );

    final chat = ChatState(FakeLlmUseCase(), mcp);
    await chat.load();

    final settings = SettingsState();
    await chat.sendUserMessage('Hello', settings);

    expect(chat.messages.last.text, 'LLM reply');
    expect(chat.messages.last.structuredContent, isNotNull);
    expect(chat.messages.last.structuredContent!['summary'], 'ok');
  });

  test('ChatState does not attach structuredContent when MCP fails', () async {
    late StreamChannelController<dynamic> ctrl;
    final mcp = McpClient(
      url: 'ws://test',
      connector: (uri) async {
        ctrl = StreamChannelController<dynamic>();
        // Respond with capabilities ok, summarize error
        ctrl.foreign.stream.listen((data) {
          final map = jsonDecode(data as String) as Map<String, dynamic>;
          final id = map['id'];
          final method = map['method'] as String?;
          if (method == 'capabilities') {
            ctrl.foreign.sink.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'tools': ['summarize']},
            }));
          } else {
            ctrl.foreign.sink.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'error': {'code': -32000, 'message': 'boom'},
            }));
          }
        });
        return ctrl.local;
      },
    );

    final chat = ChatState(FakeLlmUseCase(), mcp);
    await chat.load();

    final settings = SettingsState();
    await chat.sendUserMessage('Hello', settings);

    expect(chat.messages.last.text, 'LLM reply');
    // При ошибке MCP агент не добавляет structuredContent
    expect(chat.messages.last.structuredContent, isNull);
  });
}
