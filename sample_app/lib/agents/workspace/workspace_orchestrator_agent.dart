// Intents are defined at top level
import 'dart:async';
import 'dart:io';
import 'dart:developer' as dev;

import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/domain/llm_resolver.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/conversation_storage_service.dart';
import 'package:sample_app/agents/workspace/workspace_plan.dart';
import 'package:sample_app/agents/workspace/file_system_service.dart';
import 'package:sample_app/services/mcp_stdio_client.dart';
import 'package:sample_app/agents/workspace/workspace_fs_mcp_agent.dart';

// Intents are defined at top level
enum IntentType { 
  show_plan, 
  add_step, 
  mark_done, 
  clear_plan, 
  build_plan, 
  general_chat, 
  read_file, 
  list_dir, 
  write_file,
  delete_path,
}

/// Workspace Orchestrator Agent (MVP)
/// - Совместим с IAgent/IStatefulAgent
/// - Хранит историю диалога и восстанавливает её по conversationKey
/// - На первом этапе общается через LLM и поддерживает управление планом
class WorkspaceOrchestratorAgent with AuthPolicyMixin implements IAgent, IStatefulAgent {
  static const String defaultConversationKey = 'workspace_orchestrator';

  final List<Map<String, String>> _history = <Map<String, String>>[]; // role/content
  AppSettings _settings;
  final ConversationStorageService _store = ConversationStorageService();
  String? _conversationKey;
  final Plan _plan = Plan();
  final FileSystemService _fs = FileSystemService(Directory.current.path);
  final bool _useFsMcp;
  WorkspaceFsMcpAgent? _fsMcpAgent;
  // Ожидание подтверждения выполнения плана
  bool _awaitingPlanConfirmation = false;
  List<String> _pendingPlanSteps = const <String>[];

  WorkspaceOrchestratorAgent({
    AppSettings? baseSettings,
    String? conversationKey,
    bool useFsMcp = false,
    WorkspaceFsMcpAgent? fsMcpAgent,
  })  : _settings = baseSettings ?? const AppSettings(),
        _useFsMcp = useFsMcp {
    _conversationKey = (conversationKey != null && conversationKey.trim().isNotEmpty)
        ? conversationKey.trim()
        : defaultConversationKey;
    _fsMcpAgent = fsMcpAgent;
    if (_useFsMcp && _fsMcpAgent == null) {
      // Создаём STDIO клиента и MCP-агента по умолчанию
      final exe = Platform.isWindows ? 'python' : 'python3';
      // Рабочая директория приложения — sample_app/, сервер лежит уровнем выше в mcp_servers/
      final serverPath = Platform.isWindows
          ? '..\\mcp_servers\\fs_mcp_server_py\\server.py'
          : '../mcp_servers/fs_mcp_server_py/server.py';
      final client = McpStdioClient(
        executable: exe,
        args: [serverPath],
        environment: {
          // Песочница корнем всего репозитория (AI-intensive/)
          'FS_ROOT': Directory.current.parent.path,
        },
      );
      _fsMcpAgent = WorkspaceFsMcpAgent(client: client);
    }
  }

  // ===== Smart write: detects directives like append "..."; otherwise overwrites content =====
  Future<Map<String, dynamic>?> _smartWrite(String path, String content) async {
    // Используем raw triple-quoted RegExp, чтобы безопасно содержать как одинарные, так и двойные кавычки
    final appendRe = RegExp(r'''^append\s+(?:"([^"]*)"|'([^']*)'|(.+))$''', caseSensitive: false);
    String? toAppend;
    final m = appendRe.firstMatch(content.trim());
    if (m != null) {
      toAppend = m.group(1) ?? m.group(2) ?? m.group(3);
    }

    if (toAppend != null) {
      // 1) read current content
      String current = '';
      if (_useFsMcp) {
        final r = await _fsMcpCall('fs_read', {'path': path});
        if (r != null && (r['ok'] == true || r['contentSnippet'] is String)) {
          current = (r['contentSnippet'] ?? '').toString();
        }
      } else {
        final r = await _fs.readFile(path);
        current = r.contentSnippet;
      }
      final newContent = current + toAppend;
      // 2) overwrite with combined content
      if (_useFsMcp) {
        return await _fsMcpCall('fs_write', {
          'path': path,
          'content': newContent,
          'createDirs': true,
          'overwrite': true,
        });
      } else {
        final res = await _fs.writeFile(path: path, content: newContent, createDirs: true, overwrite: true);
        return {
          'ok': res.success,
          'path': res.path,
          'bytesWritten': res.bytesWritten,
          'message': res.message,
        };
      }
    }

    // Default: overwrite as-is
    if (_useFsMcp) {
      return await _fsMcpCall('fs_write', {'path': path, 'content': content, 'createDirs': true, 'overwrite': true});
    } else {
      final res = await _fs.writeFile(path: path, content: content, createDirs: true, overwrite: true);
      return {
        'ok': res.success,
        'path': res.path,
        'bytesWritten': res.bytesWritten,
        'message': res.message,
      };
    }
  }
  

  IntentType _classifyIntent(String text) {
    final lc = text.toLowerCase().trim();
    if (lc.startsWith('покажи план') || lc.startsWith('показать план') || lc.startsWith('show plan')) {
      return IntentType.show_plan;
    }
    if (RegExp(r'^(?:добавь\s+шаг|add\s+step)\b', caseSensitive: false).hasMatch(text)) {
      return IntentType.add_step;
    }
    if (RegExp(r'^(?:сделано|готово|done|complete)\b', caseSensitive: false).hasMatch(text)) {
      return IntentType.mark_done;
    }
    if (lc.startsWith('очисти план') || lc.startsWith('clear plan')) {
      return IntentType.clear_plan;
    }
    if (lc.startsWith('составь план') || lc.startsWith('создай план') || lc.startsWith('построй план') || lc.startsWith('build plan') || lc.contains('plan for')) {
      return IntentType.build_plan;
    }
    if (RegExp(r'^(?:прочитай\s+файл|read\s+file)\b', caseSensitive: false).hasMatch(text)) {
      return IntentType.read_file;
    }
    if (RegExp(r'^(?:список\s+файлов|list\s+dir)\b', caseSensitive: false).hasMatch(text)) {
      return IntentType.list_dir;
    }
    if (RegExp(r'^(?:запиши\s+файл|write\s+file)\b', caseSensitive: false).hasMatch(text)) {
      return IntentType.write_file;
    }
    if (RegExp(r'^(?:удали|delete)\b', caseSensitive: false).hasMatch(text)) {
      return IntentType.delete_path;
    }
    return IntentType.general_chat;
  }

  // ===== IAgent =====
  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        stateful: true,
        streaming: false,
        reasoning: false,
        tools: {},
        systemPrompt: 'You are a helpful workspace orchestrator. Communicate clearly and briefly.',
        responseRules: [
          'Отвечай кратко и по делу',
          'Если задаёшь уточняющие вопросы — не выводи финальный вывод',
        ],
      );

  @override
  Future<AgentResponse> ask(AgentRequest req) async {
    await ensureAuthorized(req, action: 'ask');

    final userText = req.input.trim();
    if (userText.isEmpty) {
      return const AgentResponse(text: '', isFinal: false, mcpUsed: false);
    }

    // История: user
    _appendHistory('user', userText);
    await _persistIfPossible();

    // Если ждём подтверждения плана — проверяем ответ пользователя
    if (_awaitingPlanConfirmation) {
      final yes = _isConfirmYes(userText);
      final no = _isConfirmNo(userText);
      if (yes || no) {
        if (no) {
          _awaitingPlanConfirmation = false;
          _pendingPlanSteps = const [];
          final msg = 'Выполнение плана отменено пользователем.';
          _appendHistory('assistant', msg);
          await _persistIfPossible();
          return AgentResponse(text: msg, isFinal: true, mcpUsed: _useFsMcp);
        }
        // yes
        final steps = _pendingPlanSteps;
        _awaitingPlanConfirmation = false;
        _pendingPlanSteps = const [];
        // Информационное сообщение о старте выполнения
        final startMsg = 'Начинаю выполнение подтверждённого плана из ${steps.length} шагов…';
        _appendHistory('assistant', startMsg);
        await _persistIfPossible();

        // Выполним шаги и выводим каждый этап в чат отдельными сообщениями
        int idx = 0;
        for (final step in steps) {
          idx += 1;
          // Инфо: объявляем шаг
          _appendHistory('assistant', 'Шаг $idx: $step');
          await _persistIfPossible();

          final action = _detectFsAction(step);
          if (action == null) {
            _appendHistory('assistant', '- Пропускаю (нет подходящего агента под этот шаг)');
            await _persistIfPossible();
            continue;
          }
          final tool = action.$1;
          final args = action.$2;
          final agentName = _useFsMcp ? 'fs_mcp' : 'local_fs';

          // Инфо: какой агент/инструмент и с какими аргументами
          _appendHistory('assistant', '- Вызов инструмента: [$agentName:$tool] args=$args');
          await _persistIfPossible();

          Map<String, dynamic>? resMap;
          if (tool == 'fs_write') {
            final path = (args['path'] ?? '').toString();
            final content = (args['content'] ?? '').toString();
            resMap = await _smartWrite(path, content);
          } else {
            if (_useFsMcp) {
              resMap = await _fsMcpCall(tool, args);
            } else {
              resMap = await _callLocalFs(tool, args);
            }
          }
          final ok = resMap != null && (resMap['ok'] != false);
          final msg = (resMap != null ? (resMap['message']?.toString() ?? '') : 'нет ответа');
          _appendHistory('assistant', '  → ${ok ? 'OK' : 'ERR'} ${msg.isNotEmpty ? '- $msg' : ''}');
          await _persistIfPossible();
        }
        final doneMsg = 'Выполнение плана завершено.';
        _appendHistory('assistant', doneMsg);
        await _persistIfPossible();
        return AgentResponse(text: doneMsg, isFinal: true, mcpUsed: _useFsMcp);
      }
      // Если ответ не похож на подтверждение/отказ — напомним о необходимости подтверждения
      final reminder = 'Подтвердите выполнение плана (ответьте "да" или "нет").';
      _appendHistory('assistant', reminder);
      await _persistIfPossible();
      return AgentResponse(text: reminder, isFinal: false, mcpUsed: _useFsMcp);
    }

    // Intent routing
    final intent = _classifyIntent(userText);
    if (intent != IntentType.general_chat) {
      final handled = await _maybeHandlePlanCommand(userText, intent: intent);
      if (handled != null) return handled;
    }

    // Try file operations shortcuts before orchestration
    final fileHandled = await _maybeHandleFileCommand(userText);
    if (fileHandled != null) return fileHandled;

    // Orchestrated flow: build a plan and request confirmation
    final planSteps = await _buildStepsFor(userText);
    if (planSteps.isNotEmpty) {
      // Show plan to the user in chat
      final planMd = [
        'План выполнения:',
        for (int i = 0; i < planSteps.length; i++) '- ${planSteps[i]}'
      ].join('\n');
      _appendHistory('assistant', planMd);
      // Запрос подтверждения
      final confirmMsg = 'Подтвердить выполнение плана? Ответьте "да" для запуска или "нет" для отмены.';
      _appendHistory('assistant', confirmMsg);
      await _persistIfPossible();
      _awaitingPlanConfirmation = true;
      _pendingPlanSteps = List<String>.from(planSteps);
      return AgentResponse(text: '$planMd\n\n$confirmMsg', isFinal: false, mcpUsed: _useFsMcp);
    }

    // Fallback: обычный LLM-ответ
    final system = _buildSystemPrompt();
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': system},
      ..._history,
    ];

    try {
      final sw = Stopwatch()..start();
      final provider = _settings.selectedNetworkName;
      final sysLen = system.length;
      final histLen = _history.length;
      final usecase = resolveLlmUseCase(_settings);
      var answer = await usecase.complete(messages: messages, settings: _settings);
      final stopToken = _extractStopToken();
      if (stopToken != null && stopToken.isNotEmpty) {
        answer = answer.replaceAll(stopToken, '').trim();
      }
      _appendHistory('assistant', answer);
      await _persistIfPossible();
      sw.stop();
      final meta = <String, dynamic>{
        'llm': {
          'provider': provider,
          'systemLength': sysLen,
          'historyMessages': histLen,
          'durationMs': sw.elapsedMilliseconds,
          'inputPreview': userText.substring(0, userText.length > 120 ? 120 : userText.length),
          'answerLength': answer.length,
        }
      };
      dev.log('LLM call completed in ${sw.elapsedMilliseconds} ms (provider=$provider, history=$histLen, sysLen=$sysLen)',
          name: 'WorkspaceOrchestratorAgent');
      return AgentResponse(text: answer, isFinal: true, mcpUsed: false, meta: meta);
    } catch (e) {
      final err = 'Ошибка LLM: $e';
      _appendHistory('assistant', err);
      await _persistIfPossible();
      return AgentResponse(text: err, isFinal: true, mcpUsed: false, meta: {'error': e.toString()});
    }
  }

  @override
  Stream<AgentEvent>? start(AgentRequest req) => null; // no streaming in MVP

  @override
  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  @override
  void dispose() {
    _fsMcpAgent?.dispose();
  }

  // ===== IStatefulAgent =====
  @override
  void clearHistory() => _history.clear();

  @override
  int get historyDepth => _settings.historyDepth;

  // ===== UI helpers =====
  Future<List<Map<String, String>>> setConversationKey(String? key) async {
    _conversationKey = (key != null && key.trim().isNotEmpty) ? key.trim() : null;
    if (_conversationKey != null) {
      final loaded = await _store.load(_conversationKey!);
      _history
        ..clear()
        ..addAll(loaded);
    }
    return List<Map<String, String>>.from(_history);
  }

  Future<void> clearHistoryAndPersist() async {
    _history.clear();
    final key = _conversationKey;
    if (key != null && key.isNotEmpty) {
      await _store.clear(key);
    }
  }

  List<Map<String, String>> exportHistory() => List<Map<String, String>>.from(_history);

  // ===== Internals =====
  void _appendHistory(String role, String content) {
    final limit = _settings.historyDepth.clamp(0, 100);
    _history.add({'role': role, 'content': content});
    if (_history.length > limit) {
      _history.removeRange(0, _history.length - limit);
    }
  }

  Future<void> _persistIfPossible() async {
    final key = _conversationKey;
    if (key != null && key.isNotEmpty) {
      await _store.save(key, _history);
    }
  }

  String _buildSystemPrompt() {
    final base = _settings.systemPrompt;
    final role = capabilities.systemPrompt ?? '';
    final rules = capabilities.responseRules.join('\n- ');
    final rulesBlock = rules.isNotEmpty ? '\n\nПравила:\n- $rules' : '';
    return '$base\n\n$role$rulesBlock'.trim();
  }

  String? _extractStopToken() => null; // not used in MVP

  // ===== План: команды пользователя =====
  Future<AgentResponse?> _maybeHandlePlanCommand(String text, {IntentType? intent}) async {
    final lc = text.toLowerCase();
    final it = intent ?? _classifyIntent(text);

    switch (it) {
      case IntentType.show_plan:
        final md = _plan.renderMarkdown();
        _appendHistory('assistant', md);
        await _persistIfPossible();
        return AgentResponse(text: md, isFinal: true);
      case IntentType.add_step:
        final addStepRe = RegExp(r'^(?:добавь\s+шаг|add\s+step)\s*[:\-]?\s*(.+)$', caseSensitive: false);
        final addM = addStepRe.firstMatch(text.trim());
        final title = addM?.group(1)?.trim();
        if (title != null && title.isNotEmpty) {
          _plan.addStep(title);
          final md = _plan.renderMarkdown();
          _appendHistory('assistant', md);
          await _persistIfPossible();
          return AgentResponse(text: md, isFinal: true);
        }
        return null;
      case IntentType.mark_done:
        final doneRe = RegExp(r'^(?:сделано|готово|done|complete)\s+([0-9,\s]+)$', caseSensitive: false);
        final dm = doneRe.firstMatch(lc);
        if (dm != null) {
          final raw = dm.group(1) ?? '';
          final ids = raw
              .split(RegExp(r'[\s,]+'))
              .map((s) => int.tryParse(s))
              .whereType<int>()
              .toList(growable: false);
          if (ids.isNotEmpty) {
            _plan.markDoneByIds(ids);
            final md = _plan.renderMarkdown();
            _appendHistory('assistant', md);
            await _persistIfPossible();
            return AgentResponse(text: md, isFinal: true);
          }
        }
        return null;
      case IntentType.clear_plan:
        _plan.clear();
        final md = _plan.renderMarkdown();
        _appendHistory('assistant', md);
        await _persistIfPossible();
        return AgentResponse(text: md, isFinal: true);
      case IntentType.build_plan:
        final md = await _buildPlanFromLLM(context: text);
        _appendHistory('assistant', md);
        await _persistIfPossible();
        return AgentResponse(text: md, isFinal: true);
      case IntentType.read_file:
      case IntentType.list_dir:
      case IntentType.write_file:
      case IntentType.delete_path:
        // Делегируем обработчику файловых команд
        return await _maybeHandleFileCommand(text);
      case IntentType.general_chat:
        return null;
    }
  }

  // ===== Файловые команды =====
  Future<AgentResponse?> _maybeHandleFileCommand(String text) async {
    final t = text.trim();
    // final lower = t.toLowerCase(); // not used

    // read file: "прочитай файл <path>" | "read file <path>"
    final readRe = RegExp(r'^(?:прочитай\s+файл|read\s+file)\s+(.+)$', caseSensitive: false);
    final rm = readRe.firstMatch(t);
    if (rm != null) {
      final path = rm.group(1)!.trim();
      final resMap = _useFsMcp
          ? await _fsMcpCall('fs_read', {'path': path})
          : null;
      if (_useFsMcp && resMap != null) {
        final md = 'Файл: ${resMap['path'] ?? path}\nРазмер: ${resMap['size'] ?? '?'} байт\n\n--- Содержимое (превью) ---\n${resMap['contentSnippet'] ?? ''}';
        _appendHistory('assistant', md);
        await _persistIfPossible();
        return AgentResponse(text: md, isFinal: true, meta: {'fileOp': 'read', 'path': path, 'size': resMap['size']});
      }
      final res = await _fs.readFile(path);
      final md = res.message;
      _appendHistory('assistant', md);
      await _persistIfPossible();
      return AgentResponse(text: md, isFinal: true, meta: {'fileOp': 'read', 'path': path, 'size': res.size});
    }

    // list dir: "список файлов <path>" | "list dir <path>"
    final listRe = RegExp(r'^(?:список\s+файлов|list\s+dir)\s+(.+)$', caseSensitive: false);
    final lm = listRe.firstMatch(t);
    if (lm != null) {
      final path = lm.group(1)!.trim();
      if (_useFsMcp) {
        final resMap = await _fsMcpCall('fs_list', {'path': path});
        if (resMap != null) {
          final entries = (resMap['entries'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
          final md = _renderDirMarkdown(resMap['path']?.toString() ?? path, entries);
          _appendHistory('assistant', md);
          await _persistIfPossible();
          return AgentResponse(text: md, isFinal: true, meta: {'fileOp': 'list', 'path': path, 'count': entries.length});
        }
      }
      final listing = await _fs.list(path);
      final md = listing.toMarkdown();
      _appendHistory('assistant', md);
      await _persistIfPossible();
      return AgentResponse(text: md, isFinal: true, meta: {'fileOp': 'list', 'path': path, 'count': listing.entries.length});
    }

    // write file: "запиши файл <path>: <content>" | "write file <path>: <content>"
    // ВАЖНО: разделитель path/content — двоеточие с пробелом (": "), чтобы не путать с Windows-диском "D:".
    final writeRe = RegExp(r'^(?:запиши\s+файл|write\s+file)\s+(.+?)\s*:\s+([\s\S]+)$', caseSensitive: false);
    final wm = writeRe.firstMatch(t);
    if (wm != null) {
      final path = wm.group(1)!.trim();
      final content = wm.group(2) ?? '';
      final resMap = await _smartWrite(path, content);
      final textOut = resMap?['message']?.toString() ?? 'Записано ${resMap?['bytesWritten'] ?? '?'} байт в ${resMap?['path'] ?? path}';
      _appendHistory('assistant', textOut);
      await _persistIfPossible();
      return AgentResponse(text: textOut, isFinal: true, meta: {'fileOp': 'write', 'path': path, 'bytesWritten': resMap?['bytesWritten'] ?? 0});
    }

    // delete path: "удали [-r] <path>" | "delete [-r] <path>"
    final delRe = RegExp(r'^(?:удали|delete)\s+(.+)$', caseSensitive: false);
    final dm = delRe.firstMatch(t);
    if (dm != null) {
      final cmd = dm.group(1)!.trim();
      final recursive = cmd.startsWith('-r ');
      final path = recursive ? cmd.substring(3).trim() : cmd;
      if (_useFsMcp) {
        final resMap = await _fsMcpCall('fs_delete', {'path': path, 'recursive': recursive});
        if (resMap != null) {
          final md = resMap['message']?.toString() ?? 'Удалено: ${resMap['path'] ?? path}';
          _appendHistory('assistant', md);
          await _persistIfPossible();
          return AgentResponse(text: md, isFinal: true, meta: {'fileOp': 'delete', 'path': path, 'recursive': recursive});
        }
      }
      final res = await _fs.deletePath(path, recursive: recursive);
      final md = res.message;
      _appendHistory('assistant', md);
      await _persistIfPossible();
      return AgentResponse(text: md, isFinal: true, meta: {'fileOp': 'delete', 'path': path, 'recursive': recursive});
    }

    return null;
  }

  Future<Map<String, dynamic>?> _fsMcpCall(String tool, Map<String, dynamic> args) async {
    final a = _fsMcpAgent;
    if (!_useFsMcp || a == null) return null;
    try {
      final res = await a.callTool(tool, args);
      return res;
    } catch (e) {
      return {'ok': false, 'message': 'MCP error: $e'};
    }
  }

  // ===== Подтверждение выполнения плана =====
  bool _isConfirmYes(String text) {
    final t = text.trim().toLowerCase();
    return t == 'да' || t == 'ок' || t == 'хорошо' || t == 'yes' || t == 'y' || t == 'go' || t == 'confirm';
  }

  bool _isConfirmNo(String text) {
    final t = text.trim().toLowerCase();
    return t == 'нет' || t == 'no' || t == 'n' || t == 'cancel' || t == 'отмена' || t == 'стоп' || t == 'stop';
  }

  // Detect FS action from a step description. Returns (tool, args) or null.
  (String, Map<String, dynamic>)? _detectFsAction(String step) {
    final t = step.trim();
    // write file: "write file <path>: <content>"
    // Используем разделитель ": " чтобы корректно обрабатывать пути вида "D:/..."
    final writeRe = RegExp(r'^(?:запиши\s+файл|write\s+file)\s+(.+?)\s*:\s+([\s\S]+)$', caseSensitive: false);
    final wm = writeRe.firstMatch(t);
    if (wm != null) {
      final path = wm.group(1)!.trim();
      final content = wm.group(2) ?? '';
      return ('fs_write', {
        'path': path,
        'content': content,
        'createDirs': true,
        'overwrite': true,
      });
    }

    // read file: "read file <path>"
    final readRe = RegExp(r'^(?:прочитай\s+файл|read\s+file)\s+(.+)$', caseSensitive: false);
    final rm = readRe.firstMatch(t);
    if (rm != null) {
      final path = rm.group(1)!.trim();
      return ('fs_read', {'path': path});
    }

    // list dir: "list dir <path>"
    final listRe = RegExp(r'^(?:список\s+файлов|list\s+dir)\s+(.+)$', caseSensitive: false);
    final lm = listRe.firstMatch(t);
    if (lm != null) {
      final path = lm.group(1)!.trim();
      return ('fs_list', {'path': path});
    }

    // delete: "delete [-r] <path>" | "удали [-r] <path>"
    final delRe = RegExp(r'^(?:удали|delete)\s+(.+)$', caseSensitive: false);
    final dm = delRe.firstMatch(t);
    if (dm != null) {
      final cmd = dm.group(1)!.trim();
      final recursive = cmd.startsWith('-r ');
      final path = recursive ? cmd.substring(3).trim() : cmd;
      return ('fs_delete', {'path': path, 'recursive': recursive});
    }

    return null;
  }

  // Local FS execution fallback mirroring MCP response shape
  Future<Map<String, dynamic>?> _callLocalFs(String tool, Map<String, dynamic> args) async {
    switch (tool) {
      case 'fs_read':
        try {
          final path = (args['path'] ?? '').toString();
          final res = await _fs.readFile(path);
          return {
            'ok': true,
            'path': res.path,
            'size': res.size,
            'contentSnippet': res.contentSnippet,
            'message': res.message,
          };
        } catch (e) {
          return {'ok': false, 'message': 'FS read error: $e'};
        }
      case 'fs_list':
        try {
          final path = (args['path'] ?? '').toString();
          final listing = await _fs.list(path);
          final entries = listing.entries
              .map((e) => {
                    'name': e.name,
                    'isDir': e.isDir,
                    if (!e.isDir && e.size != null) 'size': e.size,
                  })
              .toList();
          return {
            'ok': true,
            'path': listing.path,
            'entries': entries,
            'message': listing.message ?? 'Список для ${listing.path}: ${entries.length} элементов',
          };
        } catch (e) {
          return {'ok': false, 'message': 'FS list error: $e'};
        }
      case 'fs_write':
        try {
          final path = (args['path'] ?? '').toString();
          final content = (args['content'] ?? '').toString();
          final createDirs = args['createDirs'] == true;
          final overwrite = args['overwrite'] == true;
          final res = await _fs.writeFile(path: path, content: content, createDirs: createDirs, overwrite: overwrite);
          return {
            'ok': res.success,
            'path': res.path,
            'bytesWritten': res.bytesWritten,
            'message': res.message,
          };
        } catch (e) {
          return {'ok': false, 'message': 'FS write error: $e'};
        }
      case 'fs_delete':
        try {
          final path = (args['path'] ?? '').toString();
          final recursive = args['recursive'] == true;
          final res = await _fs.deletePath(path, recursive: recursive);
          return {
            'ok': res.success,
            'path': res.path,
            'message': res.message,
          };
        } catch (e) {
          return {'ok': false, 'message': 'FS delete error: $e'};
        }
      default:
        return {'ok': false, 'message': 'Unsupported local tool: $tool'};
    }
  }

  String _renderDirMarkdown(String path, List<Map<String, dynamic>> entries) {
    final buf = StringBuffer();
    buf.writeln('Каталог: $path');
    if (entries.isEmpty) return buf.toString().trim() + '\n(пусто)';
    for (final e in entries) {
      final isDir = (e['isDir'] == true);
      final mark = isDir ? '[DIR]' : '[FILE]';
      final size = (!isDir && e['size'] != null) ? ' (${e['size']} bytes)' : '';
      buf.writeln('- $mark ${e['name']}$size');
    }
    return buf.toString().trim();
  }

  Future<String> _buildPlanFromLLM({required String context}) async {
    // Просим LLM составить список шагов. Просим краткие действия (7±3), одна строка на шаг.
    final sys = 'Ты — ассистент-оркестратор. Составь краткий план из 3–10 атомарных шагов ТОЛЬКО из действий, которые пользователь ЯВНО запросил. '
        'Не добавляй дополнительных этапов (генерация тестов, запуск тестов, GitHub и т.п.), если пользователь этого явно не просил. '
        'Каждый шаг — на отдельной строке, без нумерации и комментариев, только императивная формулировка действия. '
        'Если действие относится к файловой системе — формулируй его явно в формате: "write file <path>: <content>", "read file <path>", "list dir <path>", "delete [-r] <path>".';
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': 'Составь план для запроса: "$context"'},
    ];
    final usecase = resolveLlmUseCase(_settings);
    final answer = await usecase.complete(messages: messages, settings: _settings);
    final steps = _parseSteps(answer);
    if (steps.isEmpty) {
      return 'Не удалось распарсить шаги из ответа модели. Исходный ответ:\n$answer';
    }
    _plan.clear();
    _plan.addSteps(steps);
    return _plan.renderMarkdown();
  }

  List<String> _parseSteps(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final steps = <String>[];
    for (final l in lines) {
      var s = l;
      // remove leading bullets or numbering
      s = s.replaceFirst(RegExp(r'^[\-\*•\d]+[\).\-:]\s*'), '');
      if (s.isEmpty) continue;
      steps.add(s);
    }
    // If no bullets detected and text is single paragraph, try splitting by ';'
    if (steps.isEmpty && raw.contains(';')) {
      steps.addAll(raw.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty));
    }
    // Cap to 10 steps
    if (steps.length > 10) {
      return steps.sublist(0, 10);
    }
    return steps;
  }

  // Build raw steps list for orchestration using LLM, update _plan and return steps
  Future<List<String>> _buildStepsFor(String context) async {
    // Keep prompt aligned with _buildPlanFromLLM but return structured steps.
    // ВАЖНО: включай ТОЛЬКО те действия, которые пользователь ЯВНО запросил.
    final sys = 'Ты — ассистент-оркестратор. Составь краткий план из 3–10 атомарных шагов ТОЛЬКО из действий, которые пользователь ЯВНО запросил. '
        'Не добавляй дополнительных этапов (генерация тестов, запуск тестов, GitHub и т.п.), если пользователь этого явно не просил. '
        'Каждый шаг — на отдельной строке, без нумерации и комментариев, только императивная формулировка действия. '
        'Если действие относится к файловой системе — формулируй его явно в формате: "write file <path>: <content>", "read file <path>", "list dir <path>", "delete [-r] <path>".';
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': 'Составь план для запроса: "$context"'},
    ];
    final usecase = resolveLlmUseCase(_settings);
    final answer = await usecase.complete(messages: messages, settings: _settings);
    final steps = _parseSteps(answer);
    if (steps.isEmpty) return const <String>[];
    _plan
      ..clear()
      ..addSteps(steps);
    return steps;
  }
}
