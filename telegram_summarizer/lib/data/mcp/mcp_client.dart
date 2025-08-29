import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stream_channel/stream_channel.dart';

typedef WebSocketConnector = Future<StreamChannel<dynamic>> Function(Uri uri);
typedef StdioConnector = Future<StreamChannel<dynamic>> Function(String command, List<String> args);

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

enum _Transport { websocket, stdio, http }

class McpClient {
  final String url;
  final WebSocketConnector _connector;
  final StdioConnector? _stdioConnector;
  /// If true, for http/https URLs we will first attempt WebSocket (https->wss, http->ws)
  /// and only fall back to HTTP JSON-RPC if WS connection cannot be established.
  /// Kept private to avoid changing the public interface for classes implementing McpClient.
  final bool _preferWebSocketOnHttp;
  _Transport? _transport;

  StreamChannel<dynamic>? _channel;
  StreamSubscription? _sub;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  int _nextId = 1;
  void Function()? onStateChanged;
  void Function(Object error)? onErrorCallback;
  Map<String, dynamic>? _capabilitiesCache; // cached simplified capabilities
  Future<void>? _handshake; // background handshake future

  // HTTP transport state
  HttpClient? _httpClient;
  Uri? _httpBase;
  Uri? _httpEndpoint; // discovered working JSON-RPC endpoint

  McpClient({
    required this.url,
    WebSocketConnector? connector,
    StdioConnector? stdioConnector,
    bool? preferWebSocketOnHttp,
  })  : _connector = connector ?? ((uri) async => WebSocketChannel.connect(uri)),
        _stdioConnector = stdioConnector,
        _preferWebSocketOnHttp = preferWebSocketOnHttp ?? true;

  bool get isConnected {
    if (_transport == _Transport.http) {
      return _httpClient != null && _httpEndpoint != null;
    }
    return _channel != null;
  }

  Future<void> connect() async {
    if (isConnected) return;
    final input = url.trim();
    Uri? parsed = Uri.tryParse(input);
    String scheme = (parsed?.scheme ?? '').toLowerCase();
    // If no scheme provided, default to HTTPS for remote HTTP JSON-RPC (WS is not available)
    if (scheme.isEmpty) {
      try {
        parsed = Uri.parse('https://$input');
        scheme = 'https';
      } catch (_) {
        // fall back to http if https parse fails
        try { parsed = Uri.parse('http://$input'); scheme = 'http'; } catch (_) {}
      }
    }
    if (scheme == 'stdio' || scheme == 'cmd') {
      _transport = _Transport.stdio;
      final ch = await _connectStdio(input);
      _channel = ch;
    } else if (scheme == 'http' || scheme == 'https') {
      // Prefer WS first (normalize https->wss, http->ws), then fall back to HTTP JSON-RPC.
      if (_preferWebSocketOnHttp) {
        try {
          _transport = _Transport.websocket;
          final ch = await _connectWebSocket(parsed!);
          _channel = ch;
        } catch (_) {
          // Fall back to HTTP transport
          _transport = _Transport.http;
          _httpClient = HttpClient();
          _httpBase = parsed;
          // Optionally probe endpoint to fail fast
          try {
            await _httpEnsureEndpoint(timeout: const Duration(seconds: 3));
          } catch (e) {
            try { _httpClient?.close(force: true); } catch (_) {}
            _httpClient = null;
            _httpBase = null;
            rethrow;
          }
          _channel = null;
        }
      } else {
        // HTTP JSON-RPC transport (no WebSocket preferred)
        _transport = _Transport.http;
        _httpClient = HttpClient();
        _httpBase = parsed;
        try {
          await _httpEnsureEndpoint(timeout: const Duration(seconds: 3));
        } catch (e) {
          try { _httpClient?.close(force: true); } catch (_) {}
          _httpClient = null;
          _httpBase = null;
          rethrow;
        }
        _channel = null;
      }
    } else {
      _transport = _Transport.websocket;
      final ch = await _connectWebSocket(parsed ?? Uri.parse(input));
      _channel = ch;
    }
    if (_channel != null) {
      _sub = _channel!.stream.listen(_onData, onError: _onError, onDone: _onDone);
    }
    // Notify about new connection state
    try { onStateChanged?.call(); } catch (_) {}

    // Start MCP handshake (MCP 2025-06-18) in background. Ignore errors for backward compatibility.
    _handshake = _initializeHandshake().catchError((_) {});
  }

  Future<void> disconnect() async {
    final ch = _channel;
    _channel = null;
    await _sub?.cancel();
    _sub = null;

    final pending = List.of(_pending.values);
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(StateError('Disconnected'));
    }

    // Try to close the sink but don't await to avoid hangs in tests
    try {
      ch?.sink.close();
    } catch (_) {}
    // Close HTTP client if used
    if (_httpClient != null) {
      try { _httpClient!.close(force: true); } catch (_) {}
      _httpClient = null;
      _httpBase = null;
      _httpEndpoint = null;
    }
    try { onStateChanged?.call(); } catch (_) {}
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
    final ch = _channel;
    _channel = null;
    _sub?.cancel();
    _sub = null;
    try { ch?.sink.close(); } catch (_) {}

    final pending = List.of(_pending.values);
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(error);
    }
    try { onErrorCallback?.call(error); } catch (_) {}
    try { onStateChanged?.call(); } catch (_) {}
  }

  void _onDone() {
    _channel = null;
    _sub?.cancel();
    _sub = null;
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(StateError('Disconnected'));
    }
    try { onStateChanged?.call(); } catch (_) {}
  }

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (method == 'capabilities') {
      try {
        if (_capabilitiesCache != null) return Map<String, dynamic>.from(_capabilitiesCache!);
        final tools = await listTools(timeout: timeout);
        final names = tools.map((e) => e['name']?.toString() ?? '').where((e) => e.isNotEmpty).toList();
        _capabilitiesCache = {'tools': names};
        return Map<String, dynamic>.from(_capabilitiesCache!);
      } catch (e) {
        return <String, dynamic>{'tools': <String>[]};
      }
    }
    // HTTP transport: per-request POST
    if (_transport == _Transport.http) {
      return await _httpCall(method, params, timeout: timeout);
    }
    // WS/STDIO transport through StreamChannel
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
    if (_transport == _Transport.stdio) {
      ch.sink.add(jsonEncode(payload) + '\n');
    } else {
      ch.sink.add(jsonEncode(payload));
    }
    try {
      return await completer.future.timeout(timeout, onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('MCP request $method timed out after ${timeout.inSeconds}s');
      });
    } finally {
      _pending.remove(id);
    }
  }

  Future<Map<String, dynamic>> summarize(String text, {Duration timeout = const Duration(seconds: 20)}) {
    return call('summarize', {'text': text}, timeout: timeout);
  }

  Future<void> _initializeHandshake({Duration timeout = const Duration(milliseconds: 300)}) async {
    try {
      await call('initialize', {
        'protocolVersion': '2025-06-18',
        'capabilities': {
          'supportsTools': true,
        },
        'client': {
          'name': 'telegram_summarizer',
          'version': '0.1.0',
        }
      }, timeout: timeout);
    } catch (_) {
      // ignore handshake errors to keep backward compatibility
    }
  }

  Future<List<Map<String, dynamic>>> listTools({Duration timeout = const Duration(seconds: 10)}) async {
    final res = await call('tools/list', const <String, dynamic>{}, timeout: timeout);
    final tools = res['tools'];
    if (tools is List) {
      return tools.map((e) => e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map)).toList();
    }
    if (tools is List<dynamic>) {
      return tools.map((e) => e is Map ? Map<String, dynamic>.from(e as Map) : <String, dynamic>{}).toList();
    }
    if (res is Map && res.containsKey('tools') && res['tools'] is List<String>) {
      return (res['tools'] as List<String>).map((n) => {'name': n}).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> arguments, {Duration timeout = const Duration(seconds: 20)}) async {
    return call('tools/call', {
      'name': name,
      'arguments': arguments,
    }, timeout: timeout);
  }

  Future<StreamChannel<dynamic>> _connectWebSocket(Uri original) async {
    final candidates = _buildWebSocketCandidates(original);
    Object? lastError;
    for (final u in candidates) {
      try {
        final ch = await _connector(u);
        return ch;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('Failed to connect via WebSocket');
  }

  List<Uri> _buildWebSocketCandidates(Uri input) {
    Uri base;
    final scheme = (input.scheme).toLowerCase();
    if (scheme == 'http') {
      base = input.replace(scheme: 'ws');
    } else if (scheme == 'https') {
      base = input.replace(scheme: 'wss');
    } else if (scheme == 'ws' || scheme == 'wss') {
      base = input;
    } else if (scheme.isEmpty) {
      base = Uri.parse('ws://${input.toString()}');
    } else {
      base = input;
    }

    final List<Uri> candidates = [];
    candidates.add(base);
    final p = base.path.isEmpty ? '/' : base.path;
    if (p == '/' || p == '') {
      for (final extra in const ['/ws', '/mcp', '/mcp/ws']) {
        candidates.add(base.replace(path: extra));
      }
    }
    return candidates;
  }

  Future<StreamChannel<dynamic>> _connectStdio(String input) async {
    final cmdLine = input.replaceFirst(RegExp(r'^(stdio:|cmd:)'), '');
    final parts = _splitCommand(cmdLine);
    if (parts.isEmpty) {
      throw ArgumentError('Invalid stdio URL: $input');
    }
    if (_stdioConnector != null) {
      return _stdioConnector!(parts.first, parts.sublist(1));
    }
    final proc = await Process.start(parts.first, parts.sublist(1));
    final stream = proc.stdout.transform(utf8.decoder);
    final sink = _ProcessJsonSink(proc.stdin);
    final controller = StreamChannelController<dynamic>();
    final sub = stream.listen((event) {
      try { controller.local.sink.add(event); } catch (_) {}
    }, onError: (e) {
      try { controller.local.sink.addError(e); } catch (_) {}
    }, onDone: () {
      try { controller.local.sink.close(); } catch (_) {}
    });
    controller.local.stream.listen((data) {
      try { sink.add(data); } catch (_) {}
    }, onError: (_) {}, onDone: () async {
      try { await sink.close(); } catch (_) {}
      try { proc.kill(ProcessSignal.sigterm); } catch (_) {}
    });
    return controller.foreign;
  }

  List<String> _splitCommand(String cmd) {
    final List<String> result = [];
    var buf = StringBuffer();
    bool inSingle = false, inDouble = false;
    for (int i = 0; i < cmd.length; i++) {
      final ch = cmd[i];
      if (ch == "'" && !inDouble) {
        inSingle = !inSingle; continue;
      }
      if (ch == '"' && !inSingle) {
        inDouble = !inDouble; continue;
      }
      if (ch.trim().isEmpty && !inSingle && !inDouble) {
        if (buf.isNotEmpty) { result.add(buf.toString()); buf = StringBuffer(); }
        continue;
      }
      buf.write(ch);
    }
    if (buf.isNotEmpty) result.add(buf.toString());
    return result;
  }
}

extension on HttpClientResponse {
  Future<String> readAsString() async {
    return await utf8.decodeStream(this);
  }
}

// --- HTTP JSON-RPC helpers ---
extension _HttpExt on McpClient {
  Future<void> _httpEnsureEndpoint({Duration timeout = const Duration(seconds: 3)}) async {
    if (_httpEndpoint != null) return;
    final base = _httpBase;
    final client = _httpClient;
    if (base == null || client == null) {
      throw StateError('HTTP client is not initialized');
    }
    final basePath = base.path.isEmpty ? '/' : base.path;
    final List<String> pathCandidates = <String>[
      basePath == '/' ? '/' : basePath, // as is
      if (basePath == '/' || basePath.isEmpty) '/mcp',
      if (basePath == '/' || basePath.isEmpty) '/rpc',
      if (basePath == '/' || basePath.isEmpty) '/jsonrpc',
      if (basePath == '/' || basePath.isEmpty) '/api/mcp',
      if (basePath == '/' || basePath.isEmpty) '/mcp/rpc',
    ];
    // Try both schemes if necessary (some envs expose only http or only https)
    final List<Uri> schemeVariants = <Uri>{
      base,
      if (base.scheme == 'https') base.replace(scheme: 'http'),
      if (base.scheme == 'http') base.replace(scheme: 'https'),
    }.toList(growable: false);

    final List<Uri> attempted = [];
    Object? lastError;
    for (final b in schemeVariants) {
      for (final p in pathCandidates) {
        final uri = b.replace(path: p);
        attempted.add(uri);
        try {
          // Probe with a lightweight initialize request
          final payload = jsonEncode({
            'jsonrpc': '2.0', 'id': 0, 'method': 'initialize', 'params': const {}
          });
          final req = await client.postUrl(uri).timeout(timeout);
          req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
          req.add(utf8.encode(payload));
          final resp = await req.close().timeout(timeout);
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            _httpEndpoint = uri;
            return;
          }
          lastError = HttpException('HTTP ${resp.statusCode} at $uri');
        } catch (e) {
          lastError = e;
        }
      }
    }
    final attemptedStr = attempted.map((u) => u.toString()).join(', ');
    throw lastError ?? StateError('No HTTP JSON-RPC endpoint detected. Tried: $attemptedStr');
  }

  Future<Map<String, dynamic>> _httpCall(String method, Map<String, dynamic> params, {Duration timeout = const Duration(seconds: 20)}) async {
    await _httpEnsureEndpoint(timeout: timeout);
    final uri = _httpEndpoint!;
    final client = _httpClient!;
    // Unique id per request, but server may ignore it. We still send it.
    final id = _nextId++;
    final payload = <String, dynamic>{
      'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params,
    };
    final req = await client.postUrl(uri).timeout(timeout);
    req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    final bytes = utf8.encode(jsonEncode(payload));
    req.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close().timeout(timeout);
    final body = await resp.readAsString().timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException('HTTP ${resp.statusCode}: $body', uri: uri);
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded as Map);
        if (map.containsKey('error')) throw McpError.fromJson(map['error']);
        final result = map['result'];
        if (result is Map<String, dynamic>) return result;
        if (result is Map) return Map<String, dynamic>.from(result);
        return {'value': result};
      }
    } catch (e) {
      // If not JSON, server may return NDJSON last line as full response; try last line parse
      final lastLine = body.trim().split('\n').where((l) => l.trim().isNotEmpty).lastOrNull;
      if (lastLine != null) {
        final alt = jsonDecode(lastLine);
        if (alt is Map) {
          final map = Map<String, dynamic>.from(alt as Map);
          if (map.containsKey('error')) throw McpError.fromJson(map['error']);
          final result = map['result'];
          if (result is Map<String, dynamic>) return result;
          if (result is Map) return Map<String, dynamic>.from(result);
          return {'value': result};
        }
      }
      rethrow;
    }
    throw StateError('Malformed HTTP JSON-RPC response');
  }
}

extension<T> on Iterable<T> {
  T? get lastOrNull {
    final it = iterator;
    T? last;
    while (it.moveNext()) { last = it.current; }
    return last;
  }
}

class _ProcessJsonSink implements StreamSink<dynamic> {
  final IOSink _inner;
  bool _closed = false;
  _ProcessJsonSink(this._inner);

  @override
  void add(event) {
    if (_closed) return;
    final text = event is String ? event : event.toString();
    _inner.add(utf8.encode(text));
  }

  @override
  void addError(error, [StackTrace? stackTrace]) {
    // no-op
  }

  @override
  Future addStream(Stream stream) async {
    await for (final e in stream) { add(e); }
  }

  @override
  Future close() async {
    if (_closed) return;
    _closed = true;
    await _inner.flush();
    await _inner.close();
  }

  @override
  Future get done => _inner.done;
}
