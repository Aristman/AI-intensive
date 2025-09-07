import 'dart:async';
import 'dart:developer' as dev;

import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/mcp_stdio_client.dart';

/// WorkspaceFsMcpAgent — агент работы с ФС через внешний MCP сервер (STDIO).
/// Инструменты: fs_list, fs_read, fs_write, fs_delete
class WorkspaceFsMcpAgent with AuthPolicyMixin implements IToolingAgent {
  final McpStdioClient _client;
  bool _initialized = false;
  Set<String> _tools = const {};

  WorkspaceFsMcpAgent({required McpStdioClient client}) : _client = client;

  Future<void> _ensureStarted() async {
    if (!_client.isRunning) {
      dev.log('Starting MCP STDIO client process...', name: 'WorkspaceFsMcpAgent');
      await _client.start();
      dev.log('MCP STDIO client started', name: 'WorkspaceFsMcpAgent');
    }
    if (!_initialized) {
      dev.log('Initializing MCP server...', name: 'WorkspaceFsMcpAgent');
      final initRes = await _client.initialize();
      dev.log('Initialized: ${initRes.toString()}', name: 'WorkspaceFsMcpAgent');
      final tools = await _client.toolsList();
      _tools = tools.map((e) => e['name']?.toString() ?? '').where((s) => s.isNotEmpty).toSet();
      dev.log('Tools available: ${_tools.join(', ')}', name: 'WorkspaceFsMcpAgent');
      _initialized = true;
    }
  }

  @override
  AgentCapabilities get capabilities => AgentCapabilities(
        stateful: false,
        streaming: false,
        reasoning: false,
        tools: _tools,
        systemPrompt: 'You are a file system agent powered by MCP STDIO.',
        responseRules: const [
          'Соблюдай песочницу сервера',
          'Отвечай кратко, с указанием относительных путей',
        ],
      );

  @override
  Stream<AgentEvent>? start(AgentRequest req) {
    // Стриминг событий не поддерживается данным агентом
    return null;
  }

  @override
  Future<AgentResponse> ask(AgentRequest req) async {
    // Базовая подсказка: просим вызывать инструменты через callTool из UI/оркестратора
    return const AgentResponse(
      text: 'Этот агент предназначен для вызова инструментов через callTool (fs_list/fs_read/fs_write/fs_delete).',
      isFinal: true,
    );
  }

  @override
  bool supportsTool(String name) => capabilities.tools.contains(name) ||
      const {'fs_list', 'fs_read', 'fs_write', 'fs_delete'}.contains(name);

  @override
  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args, {Duration? timeout}) async {
    await _ensureStarted();
    final sw = Stopwatch()..start();
    dev.log('Calling tool "$name" with args=${args.toString()}', name: 'WorkspaceFsMcpAgent');
    switch (name) {
      case 'fs_list':
      case 'fs_read':
      case 'fs_write':
      case 'fs_delete':
        final res = await _client.callTool(name, args);
        sw.stop();
        dev.log('Tool "$name" completed in ${sw.elapsedMilliseconds} ms, result=${res.toString()}', name: 'WorkspaceFsMcpAgent');
        return res;
      default:
        throw StateError('Tool not supported: $name');
    }
  }

  @override
  void updateSettings(AppSettings settings) {}

  @override
  void dispose() {
    dev.log('Disposing WorkspaceFsMcpAgent and stopping STDIO client', name: 'WorkspaceFsMcpAgent');
    _client.stop();
  }
}
