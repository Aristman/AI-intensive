import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:telegram_summarizer/state/chat_state.dart';

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
    return 'ok';
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('applyMcpUrl switches URL and reconnects without app restart', () async {
    // Single connector that echoes capabilities for any URL
    Future<StreamChannel<dynamic>> connector(Uri uri) async {
      final ctrl = StreamChannelController<dynamic>();
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
            'result': {'ok': true},
          }));
        }
      });
      return ctrl.local;
    }

    final chat = ChatState(FakeLlmUseCase());
    await chat.load();

    await chat.applyMcpUrl('ws://one', connector: connector);
    expect(chat.mcpConnected, isTrue);
    expect(chat.currentMcpUrl, 'ws://one');

    await chat.applyMcpUrl('ws://two', connector: connector);
    expect(chat.mcpConnected, isTrue);
    expect(chat.currentMcpUrl, 'ws://two');
  });
}
