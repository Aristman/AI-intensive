// Intents are defined at top level
import 'dart:async';
import 'dart:io';
import 'dart:developer' as dev;

import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/domain/llm_resolver.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/conversation_storage_service.dart';
import 'package:sample_app/agents/workspace/workspace_plan.dart';
import 'package:sample_app/agents/workspace/workspace_file_entities.dart';

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
  write_file 
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

  WorkspaceOrchestratorAgent({AppSettings? baseSettings, String? conversationKey})
      : _settings = baseSettings ?? const AppSettings() {
    _conversationKey = (conversationKey != null && conversationKey.trim().isNotEmpty)
        ? conversationKey.trim()
        : defaultConversationKey;
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

    // Intent routing
    final intent = _classifyIntent(userText);
    if (intent != IntentType.general_chat) {
      final handled = await _maybeHandlePlanCommand(userText, intent: intent);
      if (handled != null) return handled;
    }

    // Try file operations shortcuts before calling LLM
    final fileHandled = await _maybeHandleFileCommand(userText);
    if (fileHandled != null) {
      return fileHandled;
    }

    // Общение через LLM
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
  void dispose() {}

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
        // Делегируем обработчику файловых команд
        return await _maybeHandleFileCommand(text);
      case IntentType.general_chat:
        return null;
    }
  }

  // ===== Файловые команды =====
  Future<AgentResponse?> _maybeHandleFileCommand(String text) async {
    final t = text.trim();
    final lower = t.toLowerCase();

    // read file: "прочитай файл <path>" | "read file <path>"
    final readRe = RegExp(r'^(?:прочитай\s+файл|read\s+file)\s+(.+)$', caseSensitive: false);
    final rm = readRe.firstMatch(t);
    if (rm != null) {
      final path = rm.group(1)!.trim();
      final res = await _readFilePreview(path);
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
      final listing = await _listDir(path);
      final md = listing.toMarkdown();
      _appendHistory('assistant', md);
      await _persistIfPossible();
      return AgentResponse(text: md, isFinal: true, meta: {'fileOp': 'list', 'path': path, 'count': listing.entries.length});
    }

    // write file: "запиши файл <path>: <content>" | "write file <path>: <content>"
    final writeRe = RegExp(r'^(?:запиши\s+файл|write\s+file)\s+([^:]+)\s*:\s*([\s\S]+)$', caseSensitive: false);
    final wm = writeRe.firstMatch(t);
    if (wm != null) {
      final path = wm.group(1)!.trim();
      final content = wm.group(2) ?? '';
      final res = await _writeFile(path, content);
      final textOut = res.message;
      _appendHistory('assistant', textOut);
      await _persistIfPossible();
      return AgentResponse(text: textOut, isFinal: true, meta: {'fileOp': 'write', 'path': path, 'bytesWritten': res.bytesWritten});
    }

    return null;
  }

  static const int _maxPreviewBytes = 64 * 1024; // 64 KB

  Future<FilePreview> _readFilePreview(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) {
        return FilePreview(path: path, exists: false, isDir: false, size: 0, contentSnippet: '', message: 'Файл не найден: $path');
      }
      final length = await f.length();
      final stream = f.openRead(0, length > _maxPreviewBytes ? _maxPreviewBytes : null);
      final bytes = await stream.fold<List<int>>(<int>[], (p, e) => (p..addAll(e)));
      final content = String.fromCharCodes(bytes);
      final snippet = content.length > 2000 ? content.substring(0, 2000) + '\n…' : content;
      final msg = 'Файл: $path\nРазмер: $length байт\n\n--- Содержимое (превью) ---\n$snippet';
      return FilePreview(path: path, exists: true, isDir: false, size: length, contentSnippet: snippet, message: msg);
    } catch (e) {
      return FilePreview(path: path, exists: false, isDir: false, size: 0, contentSnippet: '', message: 'Ошибка чтения файла: $e');
    }
  }

  Future<FileOpResult> _writeFile(String path, String content) async {
    try {
      final f = File(path);
      await f.create(recursive: true);
      final bytes = content.codeUnits.length;
      await f.writeAsString(content);
      return FileOpResult(success: true, path: path, bytesWritten: bytes, message: 'Записано $bytes байт в $path');
    } catch (e) {
      return FileOpResult(success: false, path: path, bytesWritten: 0, message: 'Ошибка записи: $e');
    }
  }

  Future<DirListing> _listDir(String path) async {
    try {
      final d = Directory(path);
      if (!await d.exists()) {
        return DirListing(path: path, entries: [], message: 'Директория не найдена: $path');
      }
      final children = await d.list().toList();
      final entries = <DirEntry>[];
      for (final e in children) {
        if (e is Directory) {
          entries.add(DirEntry(name: e.path.split(Platform.pathSeparator).last, isDir: true, size: null));
        } else if (e is File) {
          final size = await e.length();
          entries.add(DirEntry(name: e.path.split(Platform.pathSeparator).last, isDir: false, size: size));
        }
      }
      entries.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return DirListing(path: path, entries: entries);
    } catch (e) {
      return DirListing(path: path, entries: [], message: 'Ошибка чтения директории: $e');
    }
  }

  Future<String> _buildPlanFromLLM({required String context}) async {
    // Просим LLM составить список шагов. Просим краткие действия (7±3), одна строка на шаг.
    final sys = 'Ты — ассистент-оркестратор. Составь краткий план из 5–10 атомарных шагов для заданного запроса. '
        'Каждый шаг — на отдельной строке, без нумерации, без комментариев, только формулировка действия.';
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
}
