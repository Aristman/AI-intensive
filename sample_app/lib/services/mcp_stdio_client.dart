import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

/// Простая реализация MCP клиента поверх STDIN/STDOUT внешнего процесса.
/// Протокол: одна JSON-строка на запрос/ответ.
class McpStdioClient {
  final String executable; // e.g., 'python' or full path to python
  final List<String> args; // e.g., ['mcp_servers/fs_mcp_server_py/server.py']
  final Map<String, String>? environment;

  Process? _proc;
  IOSink? _stdin;
  late StreamSubscription<String> _outSub;
  final StreamController<Map<String, dynamic>> _events = StreamController.broadcast();

  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = <int, Completer<Map<String, dynamic>>>{};

  McpStdioClient({
    required this.executable,
    required this.args,
    this.environment,
  });

  bool get isRunning => _proc != null;

  Future<void> start() async {
    if (_proc != null) return;
    dev.log('Starting STDIO process: $executable ${args.join(' ')}', name: 'McpStdioClient');
    _proc = await Process.start(
      executable,
      args,
      environment: environment,
      runInShell: Platform.isWindows, // allow .py via file association
      workingDirectory: Directory.current.path,
    );
    _stdin = _proc!.stdin;
    _outSub = _proc!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      dev.log('<< $line', name: 'McpStdioClient');
      try {
        final obj = json.decode(line) as Map<String, dynamic>;
        final id = obj['id'];
        if (id is int) {
          final c = _pending.remove(id);
          if (c != null) c.complete(obj);
        } else {
          // события/логи без id — пробрасываем в events
          _events.add(obj);
        }
      } catch (_) {
        // игнорируем не-JSON
      }
    });
    // также читаем stderr для логов
    _proc!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      dev.log('STDERR: $line', name: 'McpStdioClient');
      _events.add({'stream': 'stderr', 'line': line});
    });
  }

  Future<void> stop() async {
    try {
      await _stdin?.close();
    } catch (_) {}
    await _outSub.cancel();
    _proc?.kill(ProcessSignal.sigterm);
    _proc = null;
  }

  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<Map<String, dynamic>> _sendRequest(String method, {Map<String, dynamic>? params}) async {
    if (_proc == null) {
      await start();
    }
    final id = _nextId++;
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };
    final line = json.encode(payload);
    dev.log('>> $line', name: 'McpStdioClient');
    _stdin!.writeln(line);
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    return c.future.timeout(const Duration(seconds: 10));
  }

  Future<Map<String, dynamic>> initialize() async => _sendRequest('initialize');

  Future<List<Map<String, dynamic>>> toolsList() async {
    final resp = await _sendRequest('tools/list');
    final result = resp['result'] as Map<String, dynamic>?;
    final tools = (result != null ? result['tools'] : null) as List<dynamic>?;
    return (tools ?? const <dynamic>[]).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> arguments) async {
    final resp = await _sendRequest('tools/call', params: {
      'name': name,
      'arguments': arguments,
    });
    final result = resp['result'] as Map<String, dynamic>?;
    if (result == null) return {'ok': false, 'error': {'message': 'Empty result'}};
    if (result['ok'] == true && result['result'] is Map<String, dynamic>) {
      return (result['result'] as Map<String, dynamic>);
    }
    return result;
  }
}
