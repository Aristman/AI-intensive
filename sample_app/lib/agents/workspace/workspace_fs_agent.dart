import 'dart:async';
import 'dart:io';

import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/agents/workspace/file_system_service.dart';

/// WorkspaceFsAgent — агент для безопасной работы с файловой системой в пределах корня workspace.
/// Поддерживаемые инструменты: fs_list, fs_read, fs_write, fs_delete
class WorkspaceFsAgent with AuthPolicyMixin implements IToolingAgent {
  final FileSystemService _fs;

  WorkspaceFsAgent({String? rootDir}) : _fs = FileSystemService(rootDir ?? Directory.current.path);

  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        stateful: false,
        streaming: false,
        reasoning: false,
        tools: {'fs_list', 'fs_read', 'fs_write', 'fs_delete'},
        systemPrompt: 'You are a secure file system agent working strictly inside a sandbox root.',
        responseRules: [
          'Всегда соблюдай песочницу: никакого выхода за пределы корня',
          'Отвечай кратко, указывай относительные пути внутри корня',
        ],
      );

  // IAgent
  @override
  Future<AgentResponse> ask(AgentRequest req) async {
    await ensureAuthorized(req, action: 'ask');
    final t = req.input.trim();
    if (t.isEmpty) {
      return const AgentResponse(text: 'Укажите команду fs_* или используйте callTool()', isFinal: true);
    }
    // Минимальный парсер простых команд (list/read/write/delete)
    try {
      if (t.toLowerCase().startsWith('list ')) {
        final path = t.substring(5).trim();
        final res = await _fs.list(path);
        return AgentResponse(text: res.toMarkdown(), isFinal: true, meta: {'tool': 'fs_list', 'path': path});
      } else if (t.toLowerCase().startsWith('read ')) {
        final path = t.substring(5).trim();
        final res = await _fs.readFile(path);
        return AgentResponse(text: res.message, isFinal: true, meta: {'tool': 'fs_read', 'path': path, 'size': res.size});
      } else if (t.toLowerCase().startsWith('write ')) {
        // формат: write <path>:\n<content>
        final parts = t.substring(6);
        final colonIdx = parts.indexOf(':');
        if (colonIdx <= 0) {
          return const AgentResponse(text: 'Формат: write <path>: <content>', isFinal: true);
        }
        final path = parts.substring(0, colonIdx).trim();
        final content = parts.substring(colonIdx + 1).trimLeft();
        final res = await _fs.writeFile(path: path, content: content, createDirs: true, overwrite: false);
        return AgentResponse(
          text: res.message,
          isFinal: true,
          meta: {'tool': 'fs_write', 'path': path, 'bytesWritten': res.bytesWritten, 'overwrite': false},
        );
      } else if (t.toLowerCase().startsWith('delete ')) {
        // delete [-r] <path>
        final cmd = t.substring(7).trim();
        final recursive = cmd.startsWith('-r ');
        final path = recursive ? cmd.substring(3).trim() : cmd;
        final res = await _fs.deletePath(path, recursive: recursive);
        return AgentResponse(text: res.message, isFinal: true, meta: {'tool': 'fs_delete', 'path': path, 'recursive': recursive});
      }
    } catch (e) {
      return AgentResponse(text: 'Ошибка: $e', isFinal: true, meta: {'error': e.toString()});
    }
    return const AgentResponse(text: 'Неизвестная команда. Используйте fs_list/fs_read/fs_write/fs_delete через callTool или текстовые команды: list/read/write/delete', isFinal: true);
  }

  @override
  Stream<AgentEvent>? start(AgentRequest req) {
    // Данный агент не поддерживает стриминг событий, возвращаем null согласно контракту IAgent.
    return null;
  }

  // IToolingAgent
  @override
  bool supportsTool(String name) => capabilities.tools.contains(name);

  @override
  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args, {Duration? timeout}) async {
    switch (name) {
      case 'fs_list':
        final path = (args['path'] ?? '.').toString();
        final res = await _fs.list(path);
        return {
          'ok': true,
          'path': res.path,
          'entries': [
            for (final e in res.entries)
              {'name': e.name, 'isDir': e.isDir, if (e.size != null) 'size': e.size}
          ],
          if (res.message != null) 'message': res.message,
        };
      case 'fs_read':
        final path = (args['path'] ?? '').toString();
        final res = await _fs.readFile(path);
        return {
          'ok': res.exists,
          'path': res.path,
          'isDir': res.isDir,
          'size': res.size,
          'contentSnippet': res.contentSnippet,
          'message': res.message,
        };
      case 'fs_write':
        final path = (args['path'] ?? '').toString();
        final content = (args['content'] ?? '').toString();
        final createDirs = (args['createDirs'] ?? false) == true;
        final overwrite = (args['overwrite'] ?? false) == true; // по умолчанию false
        final res = await _fs.writeFile(path: path, content: content, createDirs: createDirs, overwrite: overwrite);
        return {
          'ok': res.success,
          'path': res.path,
          'bytesWritten': res.bytesWritten,
          'message': res.message,
        };
      case 'fs_delete':
        final path = (args['path'] ?? '').toString();
        final recursive = (args['recursive'] ?? false) == true;
        final res = await _fs.deletePath(path, recursive: recursive);
        return {
          'ok': res.success,
          'path': res.path,
          'message': res.message,
        };
      default:
        throw StateError('Tool not supported: $name');
    }
  }

  @override
  void updateSettings(AppSettings settings) {
    // No dynamic settings for now.
  }

  @override
  void dispose() {}
}
