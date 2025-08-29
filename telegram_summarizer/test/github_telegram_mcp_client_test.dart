import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:telegram_summarizer/data/mcp/clients/github_telegram_mcp_client.dart';

void main() {
  test('GithubTelegramMcpClient.local uses ws://localhost:3001', () async {
    late Uri received;
    final client = GithubTelegramMcpClient.local(
      connector: (uri) async {
        received = uri;
        final ctrl = StreamChannelController<dynamic>();
        return ctrl.local;
      },
    );

    await client.connect();
    expect(received.scheme, equals('ws'));
    expect(received.host, equals('localhost'));
    expect(received.port, equals(3001));
    await client.disconnect();
  });

  test('createIssue sends tools/call with proper arguments', () async {
    late StreamChannelController<dynamic> ctrl;
    final client = GithubTelegramMcpClient.fromUrl(
      'ws://example',
      connector: (uri) async {
        ctrl = StreamChannelController<dynamic>();
        // Echo server: respond only to tools/call
        ctrl.foreign.stream.listen((data) async {
          final map = jsonDecode(data as String) as Map<String, dynamic>;
          final id = map['id'];
          final method = map['method'];
          if (method == 'tools/call') {
            // Validate payload
            final params = Map<String, dynamic>.from(map['params'] as Map);
            expect(params['name'], equals('create_issue'));
            final args = Map<String, dynamic>.from(params['arguments'] as Map);
            expect(args['owner'], equals('Aristman'));
            expect(args['repo'], equals('AI-intensive'));
            expect(args['title'], equals('Test issue'));
            expect(args['body'], equals('Body'));
            // Respond success
            await Future<void>.delayed(const Duration(milliseconds: 5));
            ctrl.foreign.sink.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'name': 'create_issue', 'result': {'ok': true}},
            }));
          } else if (method == 'initialize') {
            // Optional: reply quickly to initialize
            ctrl.foreign.sink.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'serverInfo': {'name': 'test'}, 'capabilities': {'tools': true}},
            }));
          }
        });
        return ctrl.local;
      },
    );

    await client.connect();
    final res = await client.createIssue(
      owner: 'Aristman',
      repo: 'AI-intensive',
      title: 'Test issue',
      body: 'Body',
    );
    expect(res['name'], equals('create_issue'));
    expect((res['result'] as Map)['ok'], isTrue);
    await client.disconnect();
  });
}
