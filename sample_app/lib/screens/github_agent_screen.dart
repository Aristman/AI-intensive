import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:sample_app/agents/reasoning_agent.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/models/message.dart';
import 'package:sample_app/screens/settings_screen.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/services/conversation_storage_service.dart';
import 'package:sample_app/widgets/safe_send_text_field.dart';
import 'package:sample_app/utils/json_utils.dart';
import 'package:sample_app/services/mcp_client.dart';
import 'package:sample_app/services/github_mcp_service.dart';

/// Строит дополнительный системный промпт для GitHub‑агента (вариант A — через ReasoningAgent).
/// Промпт динамически включает owner/repo и перечисляет инструменты MCP GitHub
/// с краткими правилами, когда что вызывать.
String buildGithubAgentExtraPrompt({
  required String owner,
  required String repo,
}) {
  final hasOwnerRepo = owner.trim().isNotEmpty && repo.trim().isNotEmpty;
  final repoLine = hasOwnerRepo ? '\nТекущий контекст репозитория: $owner/$repo.' : '';

  // Краткая инструкция по инструментам GitHub MCP
  // Обязательные/опциональные аргументы перечислены для ориентира агента.
  const toolsBlock =
      'Доступные инструменты GitHub MCP и когда их использовать:\n'
      '- get_repo(owner, repo) — чтобы получить информацию о репозитории.\n'
      '- search_repos(query, per_page?, page?) — чтобы найти репозитории по запросу.\n'
      '- create_issue(owner, repo, title, body?) — чтобы создать issue.\n'
      '- create_release(owner, repo, tag_name, name?, body?, draft?, prerelease?, target_commitish?) — чтобы создать релиз.\n'
      '- list_pull_requests(owner, repo, state?, head?, base?, sort?, direction?, per_page?, page?) — чтобы посмотреть список PR.\n'
      '- get_pull_request(owner, repo, pull_number) — чтобы получить детали конкретного PR.\n'
      '- list_pr_files(owner, repo, pull_number) — чтобы посмотреть файлы PR.';

  const policy =
      'Правила использования инструментов:\n'
      '- Если не хватает данных для обязательных аргументов (например, tag_name для релиза или pull_number для PR) — сначала задай уточняющие вопросы.\n'
      '- Если owner/repo не указаны пользователем, используй заданный выше контекст (если он есть), иначе попроси уточнить.\n'
      '- Не раскрывай технические детали реализации MCP и токены. Отвечай кратко по делу.';

  final protocol =
      'Протокол вызова инструментов (ОБЯЗАТЕЛЬНО):\n'
      '- Когда принимаешь решение ВЫПОЛНИТЬ инструмент, выведи ОДНУ строку со СТРОГО валидным JSON вида:\n'
      '  {"tool":"<имя_инструмента>", "args": { ...обязательные_и_опциональные_аргументы... }}\n'
      '- Не добавляй никаких пояснений вокруг JSON, не пиши фразы вроде "Использую инструмент".\n'
      '- Если данных недостаточно — не выводи JSON и задай уточняющие вопросы.\n'
      '- Примеры:\n'
      '  {"tool":"create_issue","args":{"owner":"$owner","repo":"$repo","title":"Bug: ....","body":"..."}}\n'
      '  {"tool":"get_repo","args":{"owner":"$owner","repo":"$repo"}}\n'
      'После исполнения результата агент отобразит итог в интерфейсе.';

  return 'Ты — GitHub‑агент. Помогаешь работать с GitHub через инструменты MCP.'
      '$repoLine\n\n$toolsBlock\n\n$policy\n\n$protocol';
}

class GitHubAgentScreen extends StatefulWidget {
  final AppSettings? initialSettings; // для тестов/инъекции
  // Фабрика для инъекции кастомного ReasoningAgent в тестах
  final ReasoningAgent Function(AppSettings settings, String extraPrompt)? agentFactory;
  // Фабрика для инъекции MCP клиента (для тестов)
  final McpClient Function()? mcpClientFactory;
  const GitHubAgentScreen({super.key, this.initialSettings, this.agentFactory, this.mcpClientFactory});

  @override
  State<GitHubAgentScreen> createState() => _GitHubAgentScreenState();
}

class _GitHubAgentScreenState extends State<GitHubAgentScreen> {
  final _ownerCtrl = TextEditingController(text: 'aristman');
  final _repoCtrl = TextEditingController(text: 'AI-intensive');
  final _queryCtrl = TextEditingController();
  final _scrollController = ScrollController();

  final _settingsService = SettingsService();
  final _convStore = ConversationStorageService();
  AppSettings? _settings;
  bool _loadingSettings = true;

  ReasoningAgent? _agent;
  final List<Message> _messages = [];
  bool _sending = false;
  Timer? _mcpIndicatorTimer;
  bool _mcpUsed = false;
  // Кэш доступных MCP-инструментов для текущего URL
  Set<String>? _mcpToolNames;
  String? _mcpToolsForUrl;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _ownerCtrl.addListener(_onOwnerRepoChanged);
    _repoCtrl.addListener(_onOwnerRepoChanged);
  }

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    _queryCtrl.dispose();
    _scrollController.dispose();
    _mcpIndicatorTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    AppSettings s = widget.initialSettings ?? await _settingsService.getSettings();
    // Включаем режим рассуждений на этом экране всегда
    s = s.copyWith(reasoningMode: true);

    setState(() {
      _settings = s;
      _loadingSettings = false;
    });

    _initAgent();
  }

  Future<void> _initAgent() async {
    if (_settings == null) return;
    final extra = buildGithubAgentExtraPrompt(
      owner: _ownerCtrl.text.trim(),
      repo: _repoCtrl.text.trim(),
    );
    if (widget.agentFactory != null) {
      _agent = widget.agentFactory!(_settings!, extra);
    } else {
      _agent = ReasoningAgent(baseSettings: _settings, extraSystemPrompt: extra);
    }
    _messages.clear();

    // Загружаем сохранённую историю для текущего репозитория и импортируем в агента
    final key = _convKey;
    if (key != null) {
      final stored = await _convStore.load(key);
      if (stored.isNotEmpty) {
        _agent!.importHistory(stored);
        // Отрисуем историю в UI
        for (final m in stored) {
          _messages.add(Message(text: m['content'] ?? '', isUser: (m['role'] == 'user')));
        }
        setState(() {});
      }
    }
  }

  void _onOwnerRepoChanged() {
    // При смене owner/repo переинициализируем агента и очищаем историю
    _initAgent();
    setState(() {});
  }

  // Локальный метод заменён на глобальную функцию buildGithubAgentExtraPrompt

  bool get _mcpReady {
    final s = _settings;
    if (s == null) return false;
    final urlOk = s.mcpServerUrl?.trim().isNotEmpty ?? false;
    return s.useMcpServer && urlOk && s.isGithubMcpEnabled;
  }

  bool get _canSendQuery {
    return _mcpReady && _ownerCtrl.text.trim().isNotEmpty && _repoCtrl.text.trim().isNotEmpty && !_sending;
  }

  Future<Set<String>> _getMcpTools() async {
    final url = _settings?.mcpServerUrl?.trim();
    if (url == null || url.isEmpty) return <String>{};
    if (_mcpToolNames != null && _mcpToolsForUrl == url) return _mcpToolNames!;
    final client = (widget.mcpClientFactory ?? () => McpClient())();
    try {
      await client.connect(url);
      await client.initialize(timeout: const Duration(seconds: 5));
      final tl = await client.toolsList(timeout: const Duration(seconds: 5));
      final tools = <String>{};
      final arr = (tl['tools'] as List?) ?? const [];
      for (final t in arr) {
        final name = (t is Map && t['name'] is String) ? t['name'] as String : null;
        if (name != null && name.trim().isNotEmpty) tools.add(name.trim());
      }
      _mcpToolNames = tools;
      _mcpToolsForUrl = url;
      dev.log('MCP tools/list cached: ${tools.join(', ')}', name: 'GitHubAgent');
      return tools;
    } catch (e, st) {
      dev.log('Failed to fetch tools/list: $e', name: 'GitHubAgent', error: e, stackTrace: st);
      return _mcpToolNames ?? <String>{};
    } finally {
      await client.close();
    }
  }

  Future<void> _openSettings() async {
    if (_settings == null) return;
    final ns = await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          initialSettings: _settings!,
          onSettingsChanged: (s) {},
        ),
      ),
    );
    if (ns != null) {
      setState(() {
        _settings = ns.copyWith(reasoningMode: true);
      });
      _initAgent();
    }
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || !_canSendQuery || _agent == null) return;

    dev.log('Send request: "$q" for ${_ownerCtrl.text.trim()}/${_repoCtrl.text.trim()}', name: 'GitHubAgent');

    setState(() {
      _messages.add(Message(text: q, isUser: true));
      _queryCtrl.clear();
      _sending = true;
      _mcpUsed = false;
    });

    _scrollToBottom();

    try {
      // Не переинициализируем агента здесь, чтобы не очищать текущий UI-список сообщений
      final res = await _agent!.ask(q);
      final rr = res['result'] as ReasoningResult;
      dev.log('Assistant response (isFinal=${rr.isFinal}, mcp_used=${res['mcp_used'] ?? false}): ${rr.text}', name: 'GitHubAgent');

      setState(() {
        _messages.add(Message(text: rr.text, isUser: false, isFinal: rr.isFinal));
        _sending = false;
        _mcpUsed = res['mcp_used'] ?? false;
      });

      if (_mcpUsed) {
        _mcpIndicatorTimer?.cancel();
        _mcpIndicatorTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _mcpUsed = false);
        });
      }

      _scrollToBottom();

      // Сохраняем историю диалога после ответа
      final key = _convKey;
      if (key != null) {
        dev.log('Persist conversation history for key=$key (len=${_agent!.exportHistory().length})', name: 'GitHubAgent');
        await _convStore.save(key, _agent!.exportHistory());
      }

      // Попробуем распознать и выполнить инструмент из ответа ассистента (например, create_issue)
      // Запускаем асинхронно, чтобы не блокировать основной поток UI
      // Ошибки и статусы выводим дополнительными сообщениями в чат
      dev.log('Start tool detection/execution for assistant text…', name: 'GitHubAgent');
      unawaited(_maybeExecuteTool(rr.text));
    } catch (e, st) {
      dev.log('Ask error: $e', name: 'GitHubAgent', error: e, stackTrace: st);
      setState(() {
        _messages.add(Message(text: 'Ошибка: $e', isUser: false));
      });
      _scrollToBottom();
    }
  }

  Future<void> _maybeExecuteTool(String assistantText) async {
    try {
      dev.log('Tool detection on assistantText: ${assistantText.length})', name: 'GitHubAgent');
      final data = tryExtractJsonMap(assistantText);
      if (data == null) {
        dev.log('No JSON command detected in assistantText', name: 'GitHubAgent');
        return; // нет структурированной команды
      }
      dev.log('Parsed JSON command: ${jsonEncode(data)}', name: 'GitHubAgent');

      // Поддерживаем поля: tool / action / mcp_tool
      final tool = (data['tool'] ?? data['action'] ?? data['mcp_tool'])?.toString().trim();
      if (tool == null || tool.isEmpty) return;

      // Аргументы могут лежать в data['args'] или на верхнем уровне
      Map<String, dynamic> args = {};
      if (data['args'] is Map<String, dynamic>) {
        args = Map<String, dynamic>.from(data['args'] as Map);
      } else {
        args = Map<String, dynamic>.from(data);
      }

      // Подстановка owner/repo из UI по умолчанию
      args['owner'] = (args['owner'] ?? _ownerCtrl.text).toString().trim();
      args['repo'] = (args['repo'] ?? _repoCtrl.text).toString().trim();
      dev.log('Tool=$tool args=${jsonEncode(args)}', name: 'GitHubAgent');

      // Ветки по инструментам
      if (tool == 'create_issue') {
        final String owner = (args['owner'] ?? '').toString().trim();
        final String repo = (args['repo'] ?? '').toString().trim();
        final String title = (args['title'] ?? '').toString().trim();
        final String body = (args['body'] ?? '').toString();

        if (owner.isEmpty || repo.isEmpty || title.isEmpty) {
          setState(() {
            _messages.add(Message(
              text: 'Не удалось выполнить create_issue: отсутствуют обязательные поля (owner/repo/title).',
              isUser: false,
            ));
          });
          _scrollToBottom();
          return;
        }

        setState(() {
          _messages.add(Message(text: 'Выполняю create_issue для $owner/$repo…', isUser: false));
          _mcpUsed = _mcpReady || _mcpUsed;
        });
        _scrollToBottom();

        Map<String, dynamic> result;
        if (_mcpReady) {
          dev.log('MCP enabled. URL=${_settings!.mcpServerUrl}', name: 'GitHubAgent');
          final client = (widget.mcpClientFactory ?? () => McpClient())();
          try {
            await client.connect(_settings!.mcpServerUrl!.trim());
            await client.initialize(timeout: const Duration(seconds: 5));
            final resp = await client.toolsCall('create_issue', {
              'owner': owner,
              'repo': repo,
              'title': title,
              if (body.isNotEmpty) 'body': body,
            }, timeout: const Duration(seconds: 12));
            result = (resp is Map<String, dynamic>)
                ? (resp['result'] as Map<String, dynamic>? ?? resp)
                : {'result': resp};
          } finally {
            await client.close();
          }
        } else {
          final svc = GithubMcpService();
          dev.log('MCP disabled. Fallback to GithubMcpService.createIssueFromEnv', name: 'GitHubAgent');
          result = await svc.createIssueFromEnv(owner, repo, title, body);
        }

        final issueNumber = result['number'];
        final issueUrl = result['html_url'] ?? result['url'] ?? '';
        final okMsg = issueNumber != null
            ? 'Issue создан: #$issueNumber $issueUrl'
            : 'Issue создан: $issueUrl';
        dev.log('create_issue success: $okMsg', name: 'GitHubAgent');

        setState(() {
          _messages.add(Message(text: okMsg, isUser: false, isFinal: true));
        });
        _scrollToBottom();

        if (_agent != null) {
          final hist = _agent!.exportHistory();
          hist.add({'role': 'assistant', 'content': okMsg});
          _agent!.importHistory(hist);
        }
        final key = _convKey;
        if (key != null && _agent != null) {
          await _convStore.save(key, _agent!.exportHistory());
        }
        return;
      }

      // Дополнительная валидация параметров для отдельных инструментов
      if (tool == 'create_release') {
        final String owner = (args['owner'] ?? '').toString().trim();
        final String repo = (args['repo'] ?? '').toString().trim();
        final String tagName = (args['tag_name'] ?? '').toString().trim();

        if (owner.isEmpty || repo.isEmpty || tagName.isEmpty) {
          setState(() {
            _messages.add(Message(
              text: 'Не удалось выполнить create_release: отсутствуют обязательные поля (owner/repo/tag_name).',
              isUser: false,
            ));
          });
          _scrollToBottom();
          return;
        }
      }

      // Generic MCP tool execution for other tools
      if (_mcpReady) {
        // Preflight: проверяем наличие инструмента на сервере
        final available = await _getMcpTools();
        if (!available.contains(tool)) {
          // Повторная попытка получить актуальный список (на случай устаревшего кэша)
          _mcpToolNames = null; // сброс кэша
          final refreshed = await _getMcpTools();
          final listStr = refreshed.isNotEmpty ? refreshed.join(', ') : '(пусто)';
          final msg = 'Инструмент "$tool" недоступен на MCP‑сервере. Доступные инструменты: $listStr.\n' 
              'Обновите сервер до версии с поддержкой "$tool" или используйте один из доступных инструментов.';
          dev.log('Tool not available on MCP server: $tool. Available: $listStr', name: 'GitHubAgent');
          setState(() {
            _messages.add(Message(text: msg, isUser: false, isFinal: true));
          });
          _scrollToBottom();
          // Сохраняем в историю
          if (_agent != null) {
            final hist = _agent!.exportHistory();
            hist.add({'role': 'assistant', 'content': msg});
            _agent!.importHistory(hist);
          }
          final key = _convKey;
          if (key != null && _agent != null) {
            await _convStore.save(key, _agent!.exportHistory());
          }
          return;
        }

        setState(() {
          _messages.add(Message(text: 'Выполняю $tool…', isUser: false));
          _mcpUsed = true;
        });
        _scrollToBottom();

        final client = (widget.mcpClientFactory ?? () => McpClient())();
        dynamic resp;
        try {
          await client.connect(_settings!.mcpServerUrl!.trim());
          await client.initialize(timeout: const Duration(seconds: 5));
          dev.log('Calling MCP tool $tool with args=${jsonEncode(args)}', name: 'GitHubAgent');
          resp = await client.toolsCall(tool, args, timeout: const Duration(seconds: 12));
        } finally {
          await client.close();
        }

        final normalized = (resp is Map<String, dynamic>) ? (resp['result'] ?? resp) : resp;
        final summary = _summarizeToolResult(tool, normalized);
        dev.log('$tool success. Summary: $summary}', name: 'GitHubAgent');

        setState(() {
          _messages.add(Message(text: summary, isUser: false, isFinal: true));
        });
        _scrollToBottom();

        if (_agent != null) {
          final hist = _agent!.exportHistory();
          hist.add({'role': 'assistant', 'content': summary});
          _agent!.importHistory(hist);
        }
        final key = _convKey;
        if (key != null && _agent != null) {
          await _convStore.save(key, _agent!.exportHistory());
        }
      } else {
        // Если MCP выключен — пока не выполняем другие инструменты
        setState(() {
          _messages.add(Message(text: 'MCP отключён — выполнение "$tool" недоступно.', isUser: false));
        });
        _scrollToBottom();
        dev.log('Skip tool $tool: MCP disabled', name: 'GitHubAgent');
      }
    } catch (e, st) {
      // Специальный случай: MCP вернул -32601 (Tool not found)
      try {
        if (e is Map && e['code'] == -32601) {
          final available = await _getMcpTools();
          final listStr = available.isNotEmpty ? available.join(', ') : '(пусто)';
          final msg = 'Инструмент недоступен на сервере (MCP -32601). Доступные инструменты: $listStr.';
          dev.log('MCP -32601 Tool not found. Available: $listStr', name: 'GitHubAgent');
          setState(() {
            _messages.add(Message(text: msg, isUser: false, isFinal: true));
          });
          _scrollToBottom();
          if (_agent != null) {
            final hist = _agent!.exportHistory();
            hist.add({'role': 'assistant', 'content': msg});
            _agent!.importHistory(hist);
          }
          final key = _convKey;
          if (key != null && _agent != null) {
            await _convStore.save(key, _agent!.exportHistory());
          }
          return;
        }
      } catch (_) {}

      dev.log('Tool execution error: $e', name: 'GitHubAgent', error: e, stackTrace: st);
      setState(() {
        _messages.add(Message(text: 'Ошибка выполнения инструмента: $e', isUser: false));
      });
      _scrollToBottom();
    }
  }

  String _summarizeToolResult(String tool, dynamic result) {
    try {
      if (tool == 'get_repo' && result is Map<String, dynamic>) {
        final full = result['full_name'] ?? '';
        final desc = result['description'] ?? '';
        return 'Репозиторий: $full\n${desc.toString()}';
      }
      if (tool == 'list_issues') {
        final list = (result is List)
            ? List<Map<String, dynamic>>.from(result)
            : (result is Map && result['items'] is List)
                ? List<Map<String, dynamic>>.from(result['items'])
                : const <Map<String, dynamic>>[];
        if (list.isEmpty) return 'Issues не найдены.';
        final top = list.take(10).toList();
        final lines = <String>[];
        for (var i = 0; i < top.length; i++) {
          final issue = top[i];
          final num = issue['number'] ?? '?';
          final title = issue['title'] ?? '';
          final state = issue['state'] ?? '';
          lines.add('#$num $title (${state.toString()})');
        }
        return lines.join('\n');
      }
      if (tool == 'create_release' && result is Map<String, dynamic>) {
        String s(Object? v) => v == null ? '' : v.toString();
        final tag = s(result['tag_name']);
        final name = s(result['name']).isEmpty ? tag : s(result['name']);
        final url = s(result['html_url'].toString().isNotEmpty ? result['html_url'] : (result['url'] ?? ''));
        final draft = result['draft'] == true;
        final prerelease = result['prerelease'] == true;
        final id = s(result['id']);
        final target = s(result['target_commitish']);
        final createdAt = s(result['created_at']);
        final publishedAt = s(result['published_at']);
        final body = s(result['body']);

        final statusParts = <String>[];
        statusParts.add(draft ? 'draft' : 'published');
        if (prerelease) statusParts.add('prerelease');

        final details = <String>[
          'Релиз создан: $name',
          if (tag.isNotEmpty) 'Tag: $tag',
          if (statusParts.isNotEmpty) 'Статус: ${statusParts.join(', ')}',
          if (id.isNotEmpty) 'ID: $id',
          if (target.isNotEmpty) 'Target: $target',
          if (createdAt.isNotEmpty) 'Создан: $createdAt',
          if (publishedAt.isNotEmpty) 'Опубликован: $publishedAt',
          if (url.isNotEmpty) 'URL: $url',
          if (body.isNotEmpty) 'Описание:\n$body',
        ];
        return details.join('\n');
      }
      if (tool == 'search_repos') {
        final list = (result is Map && result['items'] is List)
            ? List<Map<String, dynamic>>.from(result['items'])
            : (result is List ? List<Map<String, dynamic>>.from(result) : const <Map<String, dynamic>>[]);
        final top = list.take(5).toList();
        if (top.isEmpty) return 'Ничего не найдено.';
        final lines = <String>[];
        for (var i = 0; i < top.length; i++) {
          final item = top[i];
          lines.add('${i + 1}. ${item['full_name'] ?? item['name'] ?? 'repo'} — ${item['description'] ?? ''}');
        }
        return lines.join('\n');
      }
      if (tool == 'list_pull_requests') {
        final list = (result is List)
            ? List<Map<String, dynamic>>.from(result)
            : (result is Map && result['items'] is List)
                ? List<Map<String, dynamic>>.from(result['items'])
                : const <Map<String, dynamic>>[];
        if (list.isEmpty) return 'PR не найдены.';
        final top = list.take(5).toList();
        final lines = <String>[];
        for (var i = 0; i < top.length; i++) {
          final pr = top[i];
          lines.add('#${pr['number'] ?? '?'} ${pr['title'] ?? ''} (${pr['state'] ?? ''})');
        }
        return lines.join('\n');
      }
      if (tool == 'get_pull_request' && result is Map<String, dynamic>) {
        final num = result['number'] ?? '';
        final title = result['title'] ?? '';
        final url = result['html_url'] ?? result['url'] ?? '';
        return 'PR #$num: $title\n$url';
      }
      if (tool == 'list_pr_files') {
        final files = (result is List)
            ? List<Map<String, dynamic>>.from(result)
            : const <Map<String, dynamic>>[];
        if (files.isEmpty) return 'Файлы PR не найдены.';
        final top = files.take(10).toList();
        final lines = <String>[];
        for (final f in top) {
          lines.add('- ${f['filename'] ?? f['path'] ?? 'file'} (+${f['additions'] ?? 0}/-${f['deletions'] ?? 0})');
        }
        return lines.join('\n');
      }
    } catch (_) {}

    // Фолбэк: компактный вывод JSON
    try {
      return result.toString();
    } catch (_) {
      return 'Готово.';
    }
  }

  String? get _convKey {
    final owner = _ownerCtrl.text.trim();
    final repo = _repoCtrl.text.trim();
    if (owner.isEmpty || repo.isEmpty) return null;
    return 'github:$owner/$repo';
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _clearHistory() async {
    final key = _convKey;
    _agent?.clearHistory();
    setState(() {
      _messages.clear();
    });
    if (key != null) {
      await _convStore.clear(key);
    }
  }

  Widget _mcpBadge() {
    if (_mcpUsed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt, size: 14, color: Colors.green.shade700),
            const SizedBox(width: 4),
            Text('MCP used', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSettings) {
      return const Center(child: CircularProgressIndicator());
    }

    final mcpConfigured = _mcpReady;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('github_owner_field'),
                  controller: _ownerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Owner',
                    hintText: 'Напр.: aristman',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('github_repo_field'),
                  controller: _repoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Repository',
                    hintText: 'Напр.: AI-intensive',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _mcpBadge(),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('github_clear_history_btn'),
                onPressed: (_messages.isEmpty && _convKey == null) ? null : _clearHistory,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Очистить историю'),
              ),
            ],
          ),
        ),
        if (!mcpConfigured)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: MaterialBanner(
              key: const Key('github_mcp_block_banner'),
              content: const Text('MCP отключён или не сконфигурирован. Экран GitHub‑агента заблокирован.'),
              leading: const Icon(Icons.lock),
              backgroundColor: Colors.amber.shade50,
              actions: [
                TextButton.icon(
                  key: const Key('github_open_settings_btn'),
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Настройки'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8.0),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final m = _messages[index];
              return Align(
                alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  decoration: BoxDecoration(
                    color: m.isUser
                        ? Theme.of(context).colorScheme.primaryContainer
                        : (m.isFinal == true
                            ? Colors.lightGreen.shade100
                            : Theme.of(context).colorScheme.surfaceContainerHighest),
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                  child: Text(
                    m.text,
                    style: TextStyle(
                      color: m.isUser
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: SafeSendTextField(
                  key: const Key('github_query_field'),
                  controller: _queryCtrl,
                  enabled: _canSendQuery,
                  hintText: _sending
                      ? 'Ожидаем ответа...'
                      : (_mcpReady ? 'Сформулируйте задачу для GitHub‑агента…' : 'MCP отключён'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24.0),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  onSend: _send,
                ),
              ),
              const SizedBox(width: 8),
              if (_sending)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  key: const Key('github_send_btn'),
                  icon: const Icon(Icons.send),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _canSendQuery ? () => _send(_queryCtrl.text) : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
