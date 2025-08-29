import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:telegram_summarizer/agents/simple_agent.dart';
import 'package:telegram_summarizer/data/mcp/mcp_client.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:telegram_summarizer/state/settings_state.dart';

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
    client,
    Duration timeout = const Duration(seconds: 20),
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async {
    lastMessages = List<Map<String, String>>.from(messages);
    // Возвращаем фиксированный ответ
    return 'LLM ok';
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SimpleAgent.askRich injects MCP capabilities and returns structuredContent', () async {
    // MCP сервер-заглушка через кастомный connector
    late StreamChannelController<dynamic> ctrl;
    final mcp = McpClient(
      url: 'ws://test',
      connector: (uri) async {
        ctrl = StreamChannelController<dynamic>();
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
          } else if (method == 'summarize') {
            ctrl.foreign.sink.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'summary': 'ok'},
            }));
          } else {
            ctrl.foreign.sink.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': <String, dynamic>{},
            }));
          }
        });
        return ctrl.local;
      },
    );

    final recLlm = _RecordingLlm();
    final agent = SimpleAgent(recLlm, systemPrompt: 'S', mcp: mcp);

    final settings = SettingsState();
    await settings.load();
    await settings.setApiKey('k');
    await settings.setFolderId('f');

    await mcp.connect();
    await agent.refreshMcpCapabilities();

    final rich = await agent.askRich('Hello', settings);

    // 1) В сообщения LLM добавлен системный промпт с capabilities
    final msgs = recLlm.lastMessages!;
    final sysCaps = msgs.where((m) => m['role'] == 'system' && (m['content'] ?? '').contains('Capabilities:')).toList();
    expect(sysCaps, isNotEmpty);
    expect(sysCaps.last['content']!, contains('"tools":["summarize"]'));

    // 2) Возвращено structuredContent из MCP
    expect(rich.structuredContent, isNotNull);
    expect(rich.structuredContent!['summary'], 'ok');
  });
}
