import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Минимальный интерфейс клиента MCP для мокирования в тестах.
abstract class McpApi {
  Future<dynamic> toolsCall(String name, Map<String, dynamic> args, {Duration? timeout});
}

class McpClient implements McpApi {
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

  Future<dynamic> _send(
    String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
  }) {
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
    return c.future.timeout(timeout ?? const Duration(seconds: 15));
  }

  Future<Map<String, dynamic>> initialize({Duration? timeout}) async {
    final result = await _send('initialize', timeout: timeout) as Map<String, dynamic>;
    _initialized = true;
    return result;
  }

  Future<Map<String, dynamic>> toolsList({Duration? timeout}) async {
    final result = await _send('tools/list', timeout: timeout) as Map<String, dynamic>;
    return result;
  }

  @override
  Future<dynamic> toolsCall(String name, Map<String, dynamic> args, {Duration? timeout}) async {
    final result = await _send(
      'tools/call',
      params: {
        'name': name,
        'arguments': args,
      },
      timeout: timeout,
    );
    return result;
  }
}
