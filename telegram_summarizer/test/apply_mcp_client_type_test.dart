import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:telegram_summarizer/state/chat_state.dart';

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
    Duration timeout = const Duration(seconds: 20),
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async {
    return 'ok';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Simple echo connector that returns capabilities on 'capabilities' method
  Future<StreamChannel<dynamic>> _connector(Uri uri) async {
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

  test('applyMcp switches client type between github_telegram and standard', () async {
    final chat = ChatState(_FakeLlm());
    await chat.load();

    await chat.applyMcp('ws://one', 'github_telegram', connector: _connector);
    expect(chat.mcpConnected, isTrue);
    expect(chat.currentMcpUrl, 'ws://one');
    expect(chat.mcpClientTypeDebug, 'github_telegram');

    await chat.applyMcp('ws://two', 'standard', connector: _connector);
    expect(chat.mcpConnected, isTrue);
    expect(chat.currentMcpUrl, 'ws://two');
    expect(chat.mcpClientTypeDebug, 'standard');
  });
}
