import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_summarizer/data/mcp/mcp_client.dart';
import 'package:stream_channel/stream_channel.dart';

void main() {
  test('McpClient summarize success', () async {
    late StreamChannelController<dynamic> ctrl;
    final client = McpClient(
      url: 'ws://test',
      connector: (uri) async {
        ctrl = StreamChannelController<dynamic>();
        // Listen to client's outgoing messages (server receives here)
        ctrl.foreign.stream.listen((data) async {
          final map = jsonDecode(data as String) as Map<String, dynamic>;
          final id = map['id'];
          await Future<void>.delayed(const Duration(milliseconds: 10));
          ctrl.foreign.sink.add(jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {'summary': 'ok'},
          }));
        });
        return ctrl.local;
      },
    );

    await client.connect();
    final res = await client.summarize('hello', timeout: const Duration(seconds: 1));
    expect(res['summary'], 'ok');
    await client.disconnect();
  });

  test('McpClient server error', () async {
    late StreamChannelController<dynamic> ctrl;
    final client = McpClient(
      url: 'ws://test',
      connector: (uri) async {
        ctrl = StreamChannelController<dynamic>();
        ctrl.foreign.stream.listen((data) async {
          final map = jsonDecode(data as String) as Map<String, dynamic>;
          final id = map['id'];
          ctrl.foreign.sink.add(jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': -32001, 'message': 'fail'},
          }));
        });
        return ctrl.local;
      },
    );

    await client.connect();
    final future = client.summarize('x');
    await expectLater(future, throwsA(isA<McpError>()));
    await client.disconnect();
  });

  test('McpClient timeout', () async {
    late StreamChannelController<dynamic> ctrl;
    final client = McpClient(
      url: 'ws://test',
      connector: (uri) async {
        ctrl = StreamChannelController<dynamic>();
        // Do not respond to simulate timeout
        return ctrl.local;
      },
    );

    await client.connect();
    final future = client.summarize('x', timeout: const Duration(milliseconds: 50));
    await expectLater(future, throwsA(isA<TimeoutException>()));
    await client.disconnect();
  });

  test('McpClient disconnect completes pending with error', () async {
    late StreamChannelController<dynamic> ctrl;
    final client = McpClient(
      url: 'ws://test',
      connector: (uri) async {
        ctrl = StreamChannelController<dynamic>();
        return ctrl.local;
      },
    );

    await client.connect();
    final future = client.summarize('x', timeout: const Duration(seconds: 2));
    await client.disconnect();
    expect(
      future,
      throwsA(anyOf(isA<StateError>(), isA<TimeoutException>())),
    );
  });
}
