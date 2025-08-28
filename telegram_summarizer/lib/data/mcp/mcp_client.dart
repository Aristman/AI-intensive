import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stream_channel/stream_channel.dart';

typedef WebSocketConnector = Future<StreamChannel<dynamic>> Function(Uri uri);

class McpError implements Exception {
  final int code;
  final String message;
  final dynamic data;
  McpError(this.code, this.message, [this.data]);

  factory McpError.fromJson(dynamic json) {
    if (json is Map) {
      final map = Map<String, dynamic>.from(json as Map);
      return McpError(map['code'] as int? ?? -32000, map['message']?.toString() ?? 'MCP error', map['data']);
    }
    return McpError(-32000, json?.toString() ?? 'MCP error');
  }

  @override
  String toString() => 'McpError($code, $message)';
}

class McpClient {
  final String url;
  final WebSocketConnector _connector;

  StreamChannel<dynamic>? _channel;
  StreamSubscription? _sub;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  int _nextId = 1;

  McpClient({required this.url, WebSocketConnector? connector})
      : _connector = connector ?? ((uri) async => WebSocketChannel.connect(uri));

  bool get isConnected => _channel != null;

  Future<void> connect() async {
    if (isConnected) return;
    final uri = Uri.parse(url);
    final ch = await _connector(uri);
    _channel = ch;
    _sub = ch.stream.listen(_onData, onError: _onError, onDone: _onDone);
  }

  Future<void> disconnect() async {
    final ch = _channel;
    _channel = null;
    await _sub?.cancel();
    _sub = null;

    // Fail all pending first to unblock waiters
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(StateError('Disconnected'));
    }

    // Try to close the sink but don't await to avoid hangs in tests
    try {
      ch?.sink.close();
    } catch (_) {}
  }

  void _onData(dynamic data) {
    try {
      final text = data is List<int> ? utf8.decode(data) : data.toString();
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded as Map);
        final idRaw = map['id'];
        int? id;
        if (idRaw is int) id = idRaw; else if (idRaw is String) id = int.tryParse(idRaw);
        if (id != null) {
          final completer = _pending.remove(id);
          if (completer != null) {
            if (map.containsKey('error')) {
              completer.completeError(McpError.fromJson(map['error']));
            } else {
              final result = map['result'];
              if (result is Map<String, dynamic>) {
                completer.complete(result);
              } else if (result is Map) {
                completer.complete(Map<String, dynamic>.from(result));
              } else {
                completer.complete({'value': result});
              }
            }
          }
        }
      }
    } catch (_) {
      // ignore malformed frames
    }
  }

  void _onError(Object error) {
    // Complete all pending with this error
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(error);
    }
  }

  void _onDone() {
    // Channel ended: mark as disconnected and fail pending if any
    _channel = null;
    _sub?.cancel();
    _sub = null;
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(StateError('Disconnected'));
    }
  }

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final ch = _channel;
    if (ch == null) {
      throw StateError('Not connected');
    }
    final id = _nextId++;
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    ch.sink.add(jsonEncode(payload));
    try {
      return await completer.future.timeout(timeout, onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('MCP request $method timed out after ${timeout.inSeconds}s');
      });
    } finally {
      // Ensure cleanup if completed exceptionally
      _pending.remove(id);
    }
  }

  Future<Map<String, dynamic>> summarize(String text, {Duration timeout = const Duration(seconds: 20)}) {
    return call('summarize', {'text': text}, timeout: timeout);
  }
}
