import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_summarizer/data/mcp/mcp_client.dart';
import 'package:stream_channel/stream_channel.dart';

void main() {
  test('https URL is converted to wss for WebSocket', () async {
    late Uri received;
    final client = McpClient(
      url: 'https://tgtoolkit.azazazaza.work',
      connector: (uri) async {
        received = uri;
        // return inert channel
        final ctrl = StreamChannelController<dynamic>();
        return ctrl.local;
      },
    );

    await client.connect();
    expect(received.scheme, equals('wss'));
    expect(received.host, equals('tgtoolkit.azazazaza.work'));
    await client.disconnect();
  });

  test('http URL is converted to ws for WebSocket', () async {
    late Uri received;
    final client = McpClient(
      url: 'http://tgtoolkit.azazazaza.work',
      connector: (uri) async {
        received = uri;
        final ctrl = StreamChannelController<dynamic>();
        return ctrl.local;
      },
    );

    await client.connect();
    expect(received.scheme, equals('ws'));
    expect(received.host, equals('tgtoolkit.azazazaza.work'));
    await client.disconnect();
  });

  test('ws URL stays ws', () async {
    late Uri received;
    final client = McpClient(
      url: 'ws://example.com:1234',
      connector: (uri) async {
        received = uri;
        final ctrl = StreamChannelController<dynamic>();
        return ctrl.local;
      },
    );

    await client.connect();
    expect(received.scheme, equals('ws'));
    expect(received.port, equals(1234));
    await client.disconnect();
  });
}
