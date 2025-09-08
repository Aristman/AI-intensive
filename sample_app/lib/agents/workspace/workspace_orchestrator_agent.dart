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
import 'package:sample_app/agents/workspace/workspace_code_gen_agent.dart';
import 'package:sample_app/agents/auto_fix/auto_fix_agent.dart';
import 'package:sample_app/agents/auto_fix/diff_apply_agent.dart';

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
  WorkspaceCodeGenAgent? _codeGenAgent;
  AutoFixAgent? _autoFixAgent;
  DiffApplyAgent? _diffApplyAgent;
  // Внутренняя память выполнения плана: хранит служебную информацию между шагами
  final Map<String, dynamic> _memory = <String, dynamic>{};
  // Хранилище артефактов (результатов внутренних агентов)
  final List<Map<String, dynamic>> _artifacts = <Map<String, dynamic>>[]; // [{type, payload, timestamp}]
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

  // ===== Плановые шаги: анализ и автофикс =====
  bool _isAutoFixPlanStep(String step) {
    final t = step.trim().toLowerCase();
    return t == 'проанализируй и автоисправь сгенерированный код' ||
        t == 'analyze and auto-fix generated code' ||
        t == 'auto-fix generated code';
  }

  Future<void> _executeAutoFixPlanStep() async {
    final last = (_memory['last_code'] ?? '').toString();
    if (last.isEmpty) {
      _appendHistory('assistant', '- Нет сгенерированного кода для автофикса');
      await _persistIfPossible();
      return;
    }
    String? lang;
    String? task;
    final meta = _memory['last_code_meta'];
    if (meta is Map) {
      if (meta['language'] is String) lang = meta['language'] as String;
      if (meta['task'] is String) task = meta['task'] as String;
    }
    _appendHistory('assistant', '- Анализ и автофикс кода…');
    await _persistIfPossible();
    dev.log('[autofix-step] start lang=${lang ?? 'text'} task="' + _short(task ?? '', 80) + '" inLen=${last.length}', name: 'WorkspaceOrchestratorAgent');
    try {
      final fixed = await _autoFixAndApply(last, language: lang ?? 'text', task: task ?? 'auto_fix');
      if (fixed != last) {
        _memory['last_code'] = fixed;
        _rememberArtifact('code', {
          'language': lang ?? 'text',
          'task': task ?? 'auto_fix',
          'size': fixed.length,
          'preview': fixed.substring(0, fixed.length > 200 ? 200 : fixed.length),
        });
        _appendHistory('assistant', '— Автофикс применён');
        dev.log('[autofix-step] applied changed=true outLen=${fixed.length}', name: 'WorkspaceOrchestratorAgent');
      } else {
        _appendHistory('assistant', '— Изменений не требуется');
        dev.log('[autofix-step] applied changed=false outLen=${fixed.length}', name: 'WorkspaceOrchestratorAgent');
      }
    } catch (e) {
      _appendHistory('assistant', '— Ошибка автофикса: $e');
      dev.log('[autofix-step] error: $e', name: 'WorkspaceOrchestratorAgent');
    }
    await _persistIfPossible();
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
        for (int i = 0; i < steps.length; i++) {
          final step = steps[i];
          final idx = i + 1;
          // Инфо: объявляем шаг
          _appendHistory('assistant', 'Шаг $idx: $step');
          await _persistIfPossible();

          // 1) Code generation step detection and execution (если шаг сам по себе генерационный)
          final codeReq = _parseCodeGenStep(step);
          if (codeReq != null) {
            final (String lang, String task, String? targetPath) = codeReq;
            final agent = _ensureCodeGenAgent();
            _appendHistory('assistant', '- Вызов агента генерации кода (язык: ' + lang + ')');
            await _persistIfPossible();
            try {
              final res = await agent.ask(AgentRequest(
                step,
                context: {
                  'language': lang,
                  'task': task,
                  'memory_summary': _memorySummary(),
                },
              ));
              var code = res.text.trim();
              code = _stripFencedCode(code, lang).trim();
              // AutoFix выполняется отдельным шагом плана, если он присутствует
              final planHasAutoFix = (_memory['plan_has_auto_fix'] == true);
              if (!planHasAutoFix) {
                code = await _autoFixAndApply(code, language: lang, task: task);
              }
              dev.log('[gen] code ready lang=$lang len=${code.length} planHasAutoFix=$planHasAutoFix', name: 'WorkspaceOrchestratorAgent');
              // Сохраняем сгенерированный код во внутренней памяти
              _memory['last_code'] = code;
              _memory['last_code_meta'] = {
                'language': lang,
                'task': task,
                'timestamp': DateTime.now().toIso8601String(),
              };
              _rememberArtifact('code', {
                'language': lang,
                'task': task,
                'size': code.length,
                'preview': code.substring(0, code.length > 200 ? 200 : code.length),
              });

              // Если указан путь назначения в шаге — пишем туда сразу
              if (targetPath != null && targetPath.trim().isNotEmpty) {
                final raw = _sanitizePath(targetPath);
                final pth = _resolveWriteTargetPath(raw, language: lang, task: task, code: code);
                _appendHistory('assistant', '— Записал файл: ' + pth);
                await _persistIfPossible();
                await _smartWrite(pth, code);
                // Обновим память назначения
                _memory['last_target_path'] = pth;
                _memory['last_target_dir'] = File(pth).parent.path;
                _rememberArtifact('write', {
                  'path': pth,
                  'size': code.length,
                });
                continue; // к следующему шагу
              }

              // Если следующий шаг — запись файла с пустым контентом, заполняем его и пропускаем
              if ((i + 1) < steps.length) {
                final nextStep = steps[i + 1];
                final nextAction = _detectFsAction(nextStep);
                if (nextAction != null && nextAction.$1 == 'fs_write') {
                  final nArgs = nextAction.$2;
                  final nPath = _sanitizePath((nArgs['path'] ?? '').toString());
                  final nContent = (nArgs['content'] ?? '').toString();
                  if (nContent.trim().isEmpty && nPath.isNotEmpty) {
                    _appendHistory('assistant', '— Записал файл: ' + nPath);
                    await _persistIfPossible();
                    await _smartWrite(nPath, code);
                    _rememberArtifact('write', {
                      'path': nPath,
                      'size': code.length,
                    });
                    i += 1; // пропускаем следующий шаг записи
                    continue; // к следующему шагу
                  }
                }
              }

              // Если дальше по плану ещё встретится запись файла — не пишем сейчас, подставим код там
              final hasFurtherWrite = steps.skip(i + 1).any((s) => _detectFsAction(s)?.$1 == 'fs_write');
              if (hasFurtherWrite) {
                _appendHistory('assistant', '— Код сгенерирован, будет записан на следующем шаге записи');
                await _persistIfPossible();
                continue;
              }

              // Иначе — определяем директорию/имя файла и записываем автоматически (финальный случай)
              final dir = _inferTargetDirectory(steps) ?? Directory.current.path;
              final safeDir = _sanitizePath(dir);
              final filename = _inferFilenameFromCodeOrTask(code: code, task: task, language: lang);
              final sep = Platform.pathSeparator;
              final path = (safeDir.endsWith(sep) ? safeDir : (safeDir + sep)) + filename;
              _appendHistory('assistant', '— Записал файл: ' + path);
              await _persistIfPossible();
              await _smartWrite(path, code);
              _memory['last_target_path'] = path;
              _memory['last_target_dir'] = File(path).parent.path;
              _rememberArtifact('write', {
                'path': path,
                'size': code.length,
              });
            } catch (e) {
              _appendHistory('assistant', 'Ошибка генерации/записи кода: $e');
              await _persistIfPossible();
            }
            continue; // переход к следующему шагу плана
          }

          // 2) Auto-fix plan step
          if (_isAutoFixPlanStep(step)) {
            await _executeAutoFixPlanStep();
            continue;
          }

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
            var path = (args['path'] ?? '').toString();
            var content = (args['content'] ?? '').toString();
            // Если контент пустой, а следующий шаг — генерация кода, сначала сгенерируем код и запишем его.
            if (content.trim().isEmpty && (i + 1) < steps.length) {
              final nextStep = steps[i + 1];
              final gen = _parseCodeGenStep(nextStep);
              if (gen != null) {
                final (String lang, String task, String? targetPath) = gen;
                final agent = _ensureCodeGenAgent();
                _appendHistory('assistant', '- Обнаружена зависимость: сначала сгенерируем код (язык: ' + lang + '), затем запишем файл');
                await _persistIfPossible();
                try {
                  final res = await agent.ask(AgentRequest(
                    nextStep,
                    context: {
                      'language': lang,
                      'task': task,
                      'memory_summary': _memorySummary(),
                    },
                  ));
                  content = _stripFencedCode(res.text.trim(), lang).trim();
                  // AutoFix + DiffApply
                  content = await _autoFixAndApply(content, language: lang, task: task);
                  _memory['last_code'] = content;
                  _memory['last_code_meta'] = {
                    'language': lang,
                    'task': task,
                    'timestamp': DateTime.now().toIso8601String(),
                  };
                  _rememberArtifact('code', {
                    'language': lang,
                    'task': task,
                    'size': content.length,
                    'preview': content.substring(0, content.length > 200 ? 200 : content.length),
                  });
                  // Пропускаем следующий шаг генерации, т.к. мы его уже выполнили
                  i += 1;
                } catch (e) {
                  _appendHistory('assistant', 'Ошибка генерации кода перед записью файла: $e');
                  await _persistIfPossible();
                }
              }
            }
            // Если контент похож на структурированный артефакт (а не реальный код)
            // 1) Попробуем извлечь код из поля preview
            // 2) Если не получилось — подставим последний сгенерированный код из памяти
            if (_looksLikeArtifactSummary(content)) {
              final fromPreview = _extractPreviewContent(content);
              if (fromPreview != null && fromPreview.trim().isNotEmpty) {
                content = fromPreview;
                dev.log('[write] placeholder->preview extracted len=${content.length}', name: 'WorkspaceOrchestratorAgent');
              } else {
                final last = (_memory['last_code'] ?? '').toString();
                if (last.isNotEmpty) {
                  content = last;
                  _appendHistory('assistant', '— Обнаружен структурированный плейсхолдер, использую ранее сгенерированный код');
                  await _persistIfPossible();
                  dev.log('[write] placeholder->last_code len=${content.length}', name: 'WorkspaceOrchestratorAgent');
                }
              }
            }
            // Если после всех попыток контент пустой или содержит плейсхолдер — подставляем последний сгенерированный код из памяти
            final trimmed = content.trim();
            if (trimmed.isEmpty || _isGeneratedPlaceholder(trimmed)) {
              final last = (_memory['last_code'] ?? '').toString();
              if (last.isNotEmpty) {
                content = last;
                _appendHistory('assistant', '— Использую ранее сгенерированный код из памяти для записи файла');
                await _persistIfPossible();
                dev.log('[write] empty/placeholder->last_code len=${content.length}', name: 'WorkspaceOrchestratorAgent');
              }
            }
            // Перед записью — автофикс содержимого (если известно language, иначе по расширению пути)
            String? lang;
            final meta = _memory['last_code_meta'];
            if (meta is Map && meta['language'] is String) lang = (meta['language'] as String);
            lang ??= _inferLanguageFromPath(path);
            final taskCtx = (meta is Map) ? (meta['task']?.toString()) : null;
            try {
              final planHasAutoFix = (_memory['plan_has_auto_fix'] == true);
              if (!planHasAutoFix) {
                final before = content.length;
                content = await _autoFixAndApply(content, language: lang ?? 'text', task: taskCtx ?? 'fs_write');
                dev.log('[write] inline autofix done lang=${lang ?? 'text'} before=$before after=${content.length}', name: 'WorkspaceOrchestratorAgent');
              }
            } catch (_) {}
            // Разрешаем целевой путь: если это директория — подставим имя файла
            if (meta is Map && meta['language'] is String) lang = (meta['language'] as String);
            path = _resolveWriteTargetPath(path, language: lang, task: taskCtx, code: (_memory['last_code']?.toString()));
            // Нормализуем путь к абсолютному
            final absPath = _resolveWriteTargetPath(path, language: lang, task: taskCtx, code: (_memory['last_code']?.toString()));
            dev.log('[write] target=$absPath len=${content.length}', name: 'WorkspaceOrchestratorAgent');
            // Если уже писали такой же контент по этому пути в рамках текущего плана — пропустим
            final lastPath = (_memory['last_target_path'] ?? '').toString();
            final lastCode = (_memory['last_code'] ?? '').toString();
            if (absPath == lastPath && content.trim() == lastCode.trim()) {
              _appendHistory('assistant', '— Пропускаю повторную запись: файл уже создан ' + absPath);
              await _persistIfPossible();
              resMap = {'ok': true, 'message': 'skipped duplicate write'};
            } else {
              resMap = await _smartWrite(absPath, content);
              path = absPath;
              // Обновим память назначения
              _memory['last_target_path'] = path;
              _memory['last_target_dir'] = File(path).parent.path;
              _rememberArtifact('write', {
                'path': path,
                'size': (content.length),
              });
              dev.log('[write] done path=$absPath bytes=${(resMap?['bytesWritten'] ?? 0)}', name: 'WorkspaceOrchestratorAgent');
            }
          } else {
            if (_useFsMcp) {
              resMap = await _fsMcpCall(tool, args);
            } else {
              resMap = await _callLocalFs(tool, args);
            }
          }
          // Если это чтение каталога/файла — выведем детальный результат
          if (tool == 'fs_list' && resMap != null) {
            final entries = (resMap['entries'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
            final path = resMap['path']?.toString() ?? (args['path']?.toString() ?? '');
            final md = _renderDirMarkdown(path, entries);
            _appendHistory('assistant', md);
            await _persistIfPossible();
            _rememberArtifact('list', {
              'path': path,
              'count': entries.length,
            });
          } else if (tool == 'fs_read' && resMap != null) {
            final path = resMap['path']?.toString() ?? (args['path']?.toString() ?? '');
            final size = resMap['size'];
            final snippet = (resMap['contentSnippet'] ?? '').toString();
            final md = 'Файл: $path\nРазмер: ${size ?? '?'} байт\n\n--- Содержимое (превью) ---\n$snippet';
            _appendHistory('assistant', md);
            await _persistIfPossible();
            _rememberArtifact('read', {
              'path': path,
              'size': size,
              'preview': snippet.substring(0, snippet.length > 200 ? 200 : snippet.length),
            });
          } else if (tool == 'fs_delete' && resMap != null) {
            final path = resMap['path']?.toString() ?? (args['path']?.toString() ?? '');
            _rememberArtifact('delete', {
              'path': path,
              'recursive': (args['recursive'] == true),
            });
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
      final planMd = _plan.renderHumanMarkdown();
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
    // Прокидываем настройки во вложенных агентов
    final a = _codeGenAgent;
    if (a != null) {
      a.updateSettings(settings);
    }
  }

  @override
  void dispose() {
    _fsMcpAgent?.dispose();
    _codeGenAgent?.dispose();
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
        final md = _plan.renderHumanMarkdown();
        _appendHistory('assistant', md);
        await _persistIfPossible();
        return AgentResponse(text: md, isFinal: true);
      case IntentType.add_step:
        final addStepRe = RegExp(r'^(?:добавь\s+шаг|add\s+step)\s*[:\-]?\s*(.+)$', caseSensitive: false);
        final addM = addStepRe.firstMatch(text.trim());
        final title = addM?.group(1)?.trim();
        if (title != null && title.isNotEmpty) {
          _plan.addStep(title);
          final md = _plan.renderHumanMarkdown();
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
            final md = _plan.renderHumanMarkdown();
            _appendHistory('assistant', md);
            await _persistIfPossible();
            return AgentResponse(text: md, isFinal: true);
          }
        }
        return null;
      case IntentType.clear_plan:
        _plan.clear();
        final md = _plan.renderHumanMarkdown();
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

  // ===== Code generation helpers =====
  WorkspaceCodeGenAgent _ensureCodeGenAgent() {
    return _codeGenAgent ??= WorkspaceCodeGenAgent(baseSettings: _settings);
  }

  // Parses code generation step. Supported formats:
  // - "сгенерируй код <lang>: <task>"
  // - "создай код <lang>: <task>"
  // - "generate code <lang>: <task>"
  // - "create code <lang>: <task>"
  // Optional target annotation (recommended): "=> write to <absolute_path>" / "=> запиши в <absolute_path>"
  (String, String, String?)? _parseCodeGenStep(String step) {
    final t = step.trim();
    final reRu = RegExp(r'^(?:сгенерируй\s+код|создай\s+код)\s+(.+?)\s*:\s+([\s\S]*?)(?:\s*=>\s*(?:запиши\s+в|записать\s+в|write\s+to)\s+(.+))?$', caseSensitive: false);
    final mRu = reRu.firstMatch(t);
    if (mRu != null) {
      return (mRu.group(1)!.trim(), mRu.group(2)!.trim(), mRu.group(3)?.trim());
    }
    final reEn = RegExp(r'^(?:generate\s+code|create\s+code)\s+(.+?)\s*:\s+([\s\S]*?)(?:\s*=>\s*(?:write\s+to|save\s+to)\s+(.+))?$', caseSensitive: false);
    final mEn = reEn.firstMatch(t);
    if (mEn != null) {
      return (mEn.group(1)!.trim(), mEn.group(2)!.trim(), mEn.group(3)?.trim());
    }
    return null;
  }

  /// Пытается вывести целевую директорию для записи кода исходя из плана шагов.
  /// Приоритеты:
  /// 1) Первый шаг вида "create directory <path>" — берём <path>
  /// 2) Первый шаг вида "write file <path>: ..." — берём родительскую директорию
  /// 3) Иначе null
  String? _inferTargetDirectory(List<String> steps) {
    // 0) Память назначения из предыдущих шагов
    final memDir = (_memory['last_target_dir'] ?? '').toString().trim();
    if (memDir.isNotEmpty) return memDir;
    for (final s in steps) {
      final mCreate = RegExp(r'^(?:создай|create)\s+directory\s+(.+)$', caseSensitive: false).firstMatch(s.trim());
      if (mCreate != null) {
        final path = _sanitizePath(mCreate.group(1)!.trim());
        if (path.isNotEmpty) return path;
      }
    }
    for (final s in steps) {
      final mWrite = RegExp(r'^(?:запиши\s+файл|write\s+file)\s+(.+?)\s*:', caseSensitive: false).firstMatch(s.trim());
      if (mWrite != null) {
        final filePath = _sanitizePath(mWrite.group(1)!.trim());
        if (filePath.isNotEmpty) {
          final dir = File(filePath).parent.path;
          return dir;
        }
      }
    }
    return null;
  }

  /// Определяет имя файла на основании кода/задачи/языка.
  /// Приоритеты:
  /// 1) Явное имя из кода (class/def)
  /// 2) Имя из задания (class XXX или CamelCase)
  /// 3) Смысловое имя из задания (slug) + разумный суффикс
  String _inferFilenameFromCodeOrTask({required String code, required String task, required String language}) {
    final ext = _extForLanguage(language);
    final lang = language.toLowerCase();
    // 1) Имя класса/функции из кода
    final classRe = RegExp(r'\bclass\s+([A-Za-z_][A-Za-z0-9_]*)');
    final defRe = RegExp(r'\bdef\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(');
    final cm = classRe.firstMatch(code);
    if (cm != null) {
      final name = cm.group(1)!;
      return _normalizeFileNameForLang(name, lang) + ext;
    }
    final dm = defRe.firstMatch(code);
    if (dm != null && (lang.contains('python') || lang == 'py')) {
      final name = dm.group(1)!;
      return _toSnakeCase(name) + ext;
    }
    // 2) Имя из задания: "class XXX" или CamelCase слово
    final tm = classRe.firstMatch(task);
    if (tm != null) {
      final name = tm.group(1)!;
      return _normalizeFileNameForLang(name, lang) + ext;
    }
    final camelInTask = RegExp(r'\b([A-Z][A-Za-z0-9_]*)\b');
    final cam = camelInTask.firstMatch(task);
    if (cam != null) {
      final name = cam.group(1)!;
      return _normalizeFileNameForLang(name, lang) + ext;
    }
    // 3) Смысловой slug из задания (RU/EN)
    final slug = _slugFromTask(task, lang);
    if (slug.isNotEmpty) return slug + ext;
    // Fallback: более читаемый, чем timestamp
    return 'app$ext';
  }

  String _normalizeFileNameForLang(String base, String lang) {
    if (lang.contains('python') || lang == 'py' || lang.contains('javascript') || lang == 'js' || lang.contains('typescript') || lang == 'ts' || lang.contains('ruby') || lang == 'rb' || lang.contains('php') || lang.contains('go')) {
      return _toSnakeCase(base);
    }
    // Для Java/Kotlin/C#/C++ — оставляем PascalCase
    return base;
  }

  String _toSnakeCase(String s) {
    final r1 = s.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m.group(1)}_${m.group(2)}');
    final r2 = r1.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    return r2.toLowerCase().replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  }

  String _toPascalCase(List<String> words) {
    return words.map((w) => w.isEmpty ? w : (w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))).join();
  }

  String _transliterateRuToLat(String s) {
    const map = {
      'а':'a','б':'b','в':'v','г':'g','д':'d','е':'e','ё':'e','ж':'zh','з':'z','и':'i','й':'y','к':'k','л':'l','м':'m','н':'n','о':'o','п':'p','р':'r','с':'s','т':'t','у':'u','ф':'f','х':'h','ц':'c','ч':'ch','ш':'sh','щ':'sch','ь':'','ы':'y','ъ':'','э':'e','ю':'yu','я':'ya'
    };
    final sb = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final low = ch.toLowerCase();
      if (map.containsKey(low)) {
        final tr = map[low]!;
        sb.write(ch == low ? tr : (tr.isEmpty ? '' : (tr[0].toUpperCase() + tr.substring(1))));
      } else {
        sb.write(ch);
      }
    }
    return sb.toString();
  }

  String _slugFromTask(String task, String lang) {
    var t = _transliterateRuToLat(task).toLowerCase();
    t = t.replaceAll(RegExp(r'[^a-z0-9\s_\-]'), ' ');
    final tokens = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final stop = <String>{
      'sozday','sgeneriruy','kod','code','class','function','method','script','generate','create','the','a','for','to','na','dlya','generator','posledovatelnosti','sequence','file','write','zapishi','v','write','to'
    };
    final filtered = <String>[];
    for (final w in tokens) {
      if (w.length <= 2) continue;
      if (stop.contains(w)) continue;
      filtered.add(w);
      if (filtered.length >= 4) break;
    }
    if (filtered.isEmpty) return '';
    // Спец-случай: если встречается "fibonacci" и "generator" — сделать fibonacci_generator
    if (tokens.contains('fibonacci') && (tokens.contains('generator') || tokens.contains('generatora') || tokens.contains('generiruet'))) {
      return 'fibonacci_generator';
    }
    // Иначе — snake_case из ключевых слов
    return filtered.join('_');
  }

  String _extForLanguage(String language) {
    final l = language.trim().toLowerCase();
    if (l.contains('java')) return '.java';
    if (l.contains('kotlin') || l == 'kt') return '.kt';
    if (l.contains('dart')) return '.dart';
    if (l.contains('python') || l == 'py') return '.py';
    if (l.contains('javascript') || l == 'js') return '.js';
    if (l.contains('typescript') || l == 'ts') return '.ts';
    if (l.contains('c#') || l.contains('csharp')) return '.cs';
    if (l.contains('c++') || l == 'cpp' || l == 'cxx') return '.cpp';
    if (l == 'c') return '.c';
    if (l.contains('swift')) return '.swift';
    if (l.contains('go') || l == 'golang') return '.go';
    if (l.contains('ruby') || l == 'rb') return '.rb';
    if (l.contains('php')) return '.php';
    return '.txt';
  }

  /// Убирает завершающие/начальные тройные бэктики и префикс языка из кода.
  String _stripFencedCode(String text, String language) {
    final fenceRe = RegExp(r'^```[a-zA-Z0-9_-]*\s*[\r\n]+([\s\S]*?)\s*```\s*$', multiLine: true);
    final m = fenceRe.firstMatch(text.trim());
    if (m != null) {
      return m.group(1) ?? text;
    }
    // Иногда модель ставит только открывающую часть
    final openRe = RegExp(r'^```[a-zA-Z0-9_-]*\s*[\r\n]+');
    var t = text;
    t = t.replaceFirst(openRe, '');
    // и/или закрывающую в конце
    if (t.trim().endsWith('```')) {
      t = t.trim();
      t = t.substring(0, t.length - 3);
    }
    return t;
  }

  /// Чистит путь: удаляет хвост в скобках (напр. "(if it doesn't exist)") и обрамляющие кавычки.
  String _sanitizePath(String raw) {
    var p = raw.trim();
    // убрать скобки в конце
    p = p.replaceFirst(RegExp(r'\s*\(.*?\)\s*$'), '');
    // убрать кавычки
    if ((p.startsWith('"') && p.endsWith('"')) || (p.startsWith("'") && p.endsWith("'"))) {
      p = p.substring(1, p.length - 1);
    }
    return p.trim();
  }

  // ===== Path and placeholder helpers =====
  bool _isGeneratedPlaceholder(String s) {
    final t = s.trim().toLowerCase();
    return t == '<generated>' ||
        t == '<<generated>>' ||
        t == '[generated]' ||
        t == '[сгенерированный код]' ||
        t == '<сгенерированный>' ||
        t == '<<сгенерированный>>';
  }

  bool _isLikelyDirectoryPath(String raw) {
    final p = raw.trim();
    if (p.endsWith('\\') || p.endsWith('/')) return true;
    // Если существует и это директория — точно да
    try {
      if (Directory(p).existsSync()) return true;
    } catch (_) {}
    // Если у последнего сегмента нет точки — тоже вероятно директория
    final parts = p.split(RegExp(r'[\\/]'))..removeWhere((e) => e.isEmpty);
    if (parts.isEmpty) return false;
    final last = parts.last;
    if (!last.contains('.')) return true;
    return false;
  }

  bool _isAbsolutePath(String p) {
    final t = p.trim();
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(t) || t.startsWith('\\\\') || t.startsWith('/');
  }

  String _joinPath(String dir, String name) {
    final sep = Platform.pathSeparator;
    final base = dir.endsWith(sep) ? dir : (dir + sep);
    return base + name;
  }

  String _resolveWriteTargetPath(String rawPath, {String? language, String? task, String? code}) {
    var p = _sanitizePath(rawPath);
    // Если указан каталог — подставим имя файла
    if (_isLikelyDirectoryPath(p)) {
      final dir = p.replaceAll(RegExp(r'[\\/]+$'), '');
      final fname = _inferFilenameFromCodeOrTask(
        code: code ?? (_memory['last_code']?.toString() ?? ''),
        task: task ?? (_memory['last_code_meta'] is Map ? (_memory['last_code_meta']['task']?.toString() ?? '') : ''),
        language: language ?? (_memory['last_code_meta'] is Map ? (_memory['last_code_meta']['language']?.toString() ?? '') : ''),
      );
      p = _joinPath(dir.isNotEmpty ? dir : (Directory.current.path), fname);
    }
    // Если путь относительный — попробуем сделать абсолютным на основе памяти или cwd
    if (!_isAbsolutePath(p)) {
      final base = (_memory['last_target_dir']?.toString() ?? '').trim();
      final root = base.isNotEmpty ? base : Directory.current.path;
      p = _joinPath(root, p);
    }
    return p;
  }

  bool _looksLikeArtifactSummary(String s) {
    final t = s.trim();
    if (!t.startsWith('{')) return false;
    // простая эвристика по ключам, которые мы используем в _rememberArtifact('code', ...)
    if (t.contains('preview:') && t.contains('language:') && t.contains('task:')) return true;
    return false;
  }

  /// Грубое извлечение содержимого поля preview из "разреженной" структуры вида
  /// {language: X, task: Y, size: N, preview: ...} с возможной вложенностью.
  /// Возвращает строку из последнего встреченного preview.
  String? _extractPreviewContent(String s) {
    try {
      final t = s.trim();
      if (!t.contains('preview:')) return null;
      // Берём ПОСЛЕДНЕЕ вхождение 'preview:' и всё, что после него
      final idx = t.lastIndexOf('preview:');
      if (idx < 0) return null;
      var tail = t.substring(idx + 'preview:'.length).trim();
      // Убираем обрамляющие фигурные скобки, если они явно окружают весь хвост
      // Пример: "{language: ..., preview: def ... }" → после среза получим "{language:..., preview: def ...}"
      // Нам нужно вытащить только часть после последнего preview, поэтому снимем внешние скобки, если они балансируют
      // Простая эвристика: если начинается с '{' и заканчивается '}', но внутри нет другого 'preview:', то убираем их
      if (tail.startsWith('{')) {
        final nextPreview = tail.indexOf('preview:', 1);
        if (nextPreview == -1 && tail.endsWith('}')) {
          tail = tail.substring(1, tail.length - 1).trim();
        }
      }
      return tail;
    } catch (_) {
      return null;
    }
  }

  String? _inferLanguageFromPath(String p) {
    final low = p.toLowerCase().trim();
    if (low.endsWith('.py')) return 'Python';
    if (low.endsWith('.dart')) return 'Dart';
    if (low.endsWith('.java')) return 'Java';
    if (low.endsWith('.kt')) return 'Kotlin';
    if (low.endsWith('.js')) return 'JavaScript';
    if (low.endsWith('.ts')) return 'TypeScript';
    if (low.endsWith('.cs')) return 'C#';
    if (low.endsWith('.cpp') || low.endsWith('.cxx') || low.endsWith('.cc')) return 'C++';
    if (low.endsWith('.c')) return 'C';
    if (low.endsWith('.swift')) return 'Swift';
    if (low.endsWith('.go')) return 'Go';
    if (low.endsWith('.rb')) return 'Ruby';
    if (low.endsWith('.php')) return 'PHP';
    return null;
  }

  // ===== Auto-fix helpers =====
  /// Выполняет базовую автопочинку сгенерированного кода перед записью.
  /// 1) Локальная нормализация: убираем хвостовые пробелы, добавляем перевод строки в конце.
  /// 2) Опционально прогоняем через AutoFixAgent (без LLM) на временном файле и применяем патчи.
  ///    Если патч содержит только diff без newContent — используем DiffApplyAgent для применения изменений.
  Future<String> _autoFixAndApply(String code, {required String language, required String task}) async {
    try {
      dev.log('[autofix] in start lang=$language task="' + _short(task, 80) + '" codeLen=${code.length}', name: 'WorkspaceOrchestratorAgent');
      // Шаг 1: локальная нормализация строк
      var normalized = code.replaceAll(RegExp(r"[ \t]+\r?$", multiLine: true), "");
      if (!normalized.endsWith('\n')) normalized += '\n';
      dev.log('[autofix] after local normalize len=${normalized.length}', name: 'WorkspaceOrchestratorAgent');

      // Если агенты не инициализированы — создадим (используем текущие настройки)
      _autoFixAgent ??= AutoFixAgent(initialSettings: _settings);
      _diffApplyAgent ??= DiffApplyAgent();

      // Шаг 2: опциональный прогон через AutoFixAgent на временном файле (без LLM)
      // Это позволяет применить базовые патчи (хвостовые пробелы/последняя строка и т.п.)
      final tmpDir = Directory.systemTemp.createTempSync('ws_orch_');
      final ext = _extForLanguage(language);
      final tmpFile = File(_joinPath(tmpDir.path, 'gen$ext'));
      await tmpFile.writeAsString(normalized);

      final req = AgentRequest(
        'auto-fix generated code',
        context: {
          'path': tmpFile.path,
          'mode': 'file',
          'useLLM': false,
          'includeLLMInApply': false,
          'language': language,
          'task': task,
        },
      );

      final stream = _autoFixAgent!.start(req);
      if (stream != null) {
        final completer = Completer<List<Map<String, dynamic>>>();
        final subs = stream.listen((ev) {
          if (ev.stage == AgentStage.pipeline_complete) {
            final meta = ev.meta ?? const {};
            final patches = (meta['patches'] as List<dynamic>? ?? const [])
                .map((e) => (e as Map).cast<String, dynamic>())
                .toList();
            if (!completer.isCompleted) completer.complete(patches);
          } else if (ev.stage == AgentStage.pipeline_error) {
            if (!completer.isCompleted) completer.complete(<Map<String, dynamic>>[]);
          }
        }, onError: (_) {
          if (!completer.isCompleted) completer.complete(<Map<String, dynamic>>[]);
        }, onDone: () {
          // если не пришёл pipeline_complete — вернём пустые патчи
          if (!completer.isCompleted) completer.complete(<Map<String, dynamic>>[]);
        });

        List<Map<String, dynamic>> patches = <Map<String, dynamic>>[];
        try {
          patches = await completer.future.timeout(const Duration(seconds: 10));
        } catch (_) {
          // таймаут/ошибка — оставим локально нормализованный код
        } finally {
          await subs.cancel();
        }

        // Применяем патчи последовательно к текущему содержимому
        var current = normalized;
        for (final p in patches) {
          final newContent = p['newContent'];
          final diff = p['diff'];
          if (newContent is String && newContent.isNotEmpty) {
            current = newContent;
            continue;
          }
          if (diff is String && diff.trim().isNotEmpty) {
            try {
              final applied = await _diffApplyAgent!.apply(
                original: current,
                diff: diff,
                settings: _settings,
              );
              if (applied != null && applied.isNotEmpty) {
                current = applied;
              }
            } catch (_) {
              // Игнорируем сбой применения diff — оставим текущее содержимое
            }
          }
        }

        try {
          // обновим normalized если патчи что-то изменили
          normalized = current;
        } catch (_) {}
      }

      // Уберём временные файлы/папки
      try {
        if (tmpFile.existsSync()) tmpFile.deleteSync();
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      } catch (_) {}

      final changed = normalized != code;
      dev.log('[autofix] out changed=$changed finalLen=${normalized.length}', name: 'WorkspaceOrchestratorAgent');
      return normalized;
    } catch (e) {
      dev.log('autoFix failed: $e', name: 'WorkspaceOrchestratorAgent');
      // В худшем случае возвращаем исходный код без изменений
      return code;
    }
  }

  // ===== Подтверждение выполнения плана =====
  void _rememberArtifact(String type, Map<String, dynamic> payload) {
    final entry = {
      'type': type,
      'payload': payload,
      'timestamp': DateTime.now().toIso8601String(),
    };
    _artifacts.add(entry);
    // ограничим размер истории артефактов
    const maxArtifacts = 200;
    if (_artifacts.length > maxArtifacts) {
      _artifacts.removeRange(0, _artifacts.length - maxArtifacts);
    }
    // быстрые ссылки в _memory
    _memory['last_$type'] = payload;
  }

  String _memorySummary({int limit = 8}) {
    final buf = StringBuffer();
    // последние N артефактов (в обратном порядке)
    final items = _artifacts.reversed.take(limit).toList().reversed;
    for (final it in items) {
      final type = (it['type'] ?? '').toString();
      final payload = (it['payload'] as Map<String, dynamic>? ?? const {});
      switch (type) {
        case 'code':
          final lang = payload['language']?.toString() ?? '';
          final task = payload['task']?.toString() ?? '';
          final size = payload['size']?.toString() ?? '';
          buf.writeln('- code: $lang, size=$size, task="' + _short(task, 80) + '"');
          break;
        case 'write':
          final path = payload['path']?.toString() ?? '';
          final size = payload['size']?.toString() ?? '';
          buf.writeln('- write: ' + _short(path, 120) + ', size=$size');
          break;
        case 'list':
          final path = payload['path']?.toString() ?? '';
          final count = payload['count']?.toString() ?? '';
          buf.writeln('- list: ' + _short(path, 120) + ', entries=$count');
          break;
        case 'read':
          final path = payload['path']?.toString() ?? '';
          final size = (payload['size']?.toString() ?? '');
          buf.writeln('- read: ' + _short(path, 120) + ', size=$size');
          break;
        case 'delete':
          final path = payload['path']?.toString() ?? '';
          buf.writeln('- delete: ' + _short(path, 120));
          break;
        default:
          buf.writeln('- $type');
      }
    }
    final lastDir = (_memory['last_target_dir'] ?? '').toString();
    final lastPath = (_memory['last_target_path'] ?? '').toString();
    if (lastDir.isNotEmpty) buf.writeln('- last_dir: ' + _short(lastDir, 120));
    if (lastPath.isNotEmpty) buf.writeln('- last_path: ' + _short(lastPath, 120));
    final s = buf.toString().trim();
    return s.isEmpty ? '(no artifacts yet)' : s;
  }

  String _short(String s, int max) {
    if (s.length <= max) return s;
    return s.substring(0, max - 1) + '…';
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
        'Всегда указывай АБСОЛЮТНЫЕ пути Windows для файловых операций. '
        'Если действие относится к файловой системе — используй формат: "write file <absolute_path>: <content>", "read file <absolute_path>", "list dir <absolute_path>", "delete [-r] <absolute_path>". '
        'Если требуется сгенерировать код — используй формат: "сгенерируй код <язык>: <задание> => write to <absolute_path>" или "generate code <language>: <task> => write to <absolute_path>".';
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': sys},
      {'role': 'system', 'content': 'Контекст (артефакты последних шагов):\n' + _memorySummary()},
      {'role': 'user', 'content': 'Составь план для запроса: "$context"'},
    ];
    final usecase = resolveLlmUseCase(_settings);
    final answer = await usecase.complete(messages: messages, settings: _settings);
    var steps = _parseSteps(answer);
    steps = _injectAutoFixSteps(steps);
    if (steps.isEmpty) {
      return 'Не удалось распарсить шаги из ответа модели. Исходный ответ:\n$answer';
    }
    _plan.clear();
    _plan.addSteps(steps);
    _memory['plan_has_auto_fix'] = steps.any(_isAutoFixPlanStep);
    return _plan.renderHumanMarkdown();
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
        'Если действие относится к файловой системе — формулируй его явно в формате: "write file <path>: <content>", "read file <path>", "list dir <path>", "delete [-r] <path>". '
        'Если требуется сгенерировать код — используй формат: "сгенерируй код <язык>: <задание>" или "generate code <language>: <task>".';
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': 'Составь план для запроса: "$context"'},
    ];
    final usecase = resolveLlmUseCase(_settings);
    final answer = await usecase.complete(messages: messages, settings: _settings);
    var steps = _parseSteps(answer);
    steps = _injectAutoFixSteps(steps);
    if (steps.isEmpty) return const <String>[];
    _plan
      ..clear()
      ..addSteps(steps);
    _memory['plan_has_auto_fix'] = steps.any(_isAutoFixPlanStep);
    return steps;
  }

  List<String> _injectAutoFixSteps(List<String> steps) {
    final out = <String>[];
    for (int i = 0; i < steps.length; i++) {
      final s = steps[i];
      out.add(s);
      final gen = _parseCodeGenStep(s);
      if (gen != null) {
        // После каждого шага генерации кода добавляем явный шаг проверки и автофикса
        out.add('проанализируй и автоисправь сгенерированный код');
      }
    }
    return out;
  }
}
