import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class McpClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  int _idCounter = 1;
  final Map<int, Completer<dynamic>> _pending = {};
  bool _initialized = false;

  bool get isConnected => _channel != null;
  bool get isInitialized => _initialized;

  Future<void> connect(String url) async {
    await close();
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _sub = _channel!.stream.listen(_onMessage, onError: (e) {
      // fail all pending
      for (final c in _pending.values) {
        if (!c.isCompleted) c.completeError(e);
      }
      _pending.clear();
    }, onDone: () {
      for (final c in _pending.values) {
        if (!c.isCompleted) c.completeError(StateError('WebSocket closed'));
      }
      _pending.clear();
      _initialized = false;
      _channel = null;
    });
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    _initialized = false;
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final id = msg['id'];
      if (id is int && _pending.containsKey(id)) {
        final c = _pending.remove(id)!;
        if (msg.containsKey('error')) {
          c.completeError(msg['error']);
        } else {
          c.complete(msg['result']);
        }
      }
    } catch (_) {
      // ignore malformed
    }
  }

  Future<dynamic> _send(String method, [Map<String, dynamic>? params]) {
    if (_channel == null) {
      throw StateError('MCP not connected');
    }
    final id = _idCounter++;
    final c = Completer<dynamic>();
    _pending[id] = c;
    final payload = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };
    _channel!.sink.add(jsonEncode(payload));
    return c.future.timeout(const Duration(seconds: 15));
  }

  Future<Map<String, dynamic>> initialize() async {
    final result = await _send('initialize') as Map<String, dynamic>;
    _initialized = true;
    return result;
  }

  Future<Map<String, dynamic>> toolsList() async {
    final result = await _send('tools/list') as Map<String, dynamic>;
    return result;
  }

  Future<dynamic> toolsCall(String name, Map<String, dynamic> args) async {
    final result = await _send('tools/call', {
      'name': name,
      'arguments': args,
    });
    return result;
  }
}
