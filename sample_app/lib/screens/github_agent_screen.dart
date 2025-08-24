import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sample_app/agents/reasoning_agent.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/models/message.dart';
import 'package:sample_app/screens/settings_screen.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/widgets/safe_send_text_field.dart';

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

  return 'Ты — GitHub‑агент. Помогаешь работать с GitHub через инструменты MCP.'
      '$repoLine\n\n$toolsBlock\n\n$policy';
}

class GitHubAgentScreen extends StatefulWidget {
  final AppSettings? initialSettings; // для тестов/инъекции
  const GitHubAgentScreen({super.key, this.initialSettings});

  @override
  State<GitHubAgentScreen> createState() => _GitHubAgentScreenState();
}

class _GitHubAgentScreenState extends State<GitHubAgentScreen> {
  final _ownerCtrl = TextEditingController(text: 'aristman');
  final _repoCtrl = TextEditingController(text: 'AI-intensive');
  final _queryCtrl = TextEditingController();
  final _scrollController = ScrollController();

  final _settingsService = SettingsService();
  AppSettings? _settings;
  bool _loadingSettings = true;

  ReasoningAgent? _agent;
  final List<Message> _messages = [];
  bool _sending = false;
  Timer? _mcpIndicatorTimer;
  bool _mcpUsed = false;

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

  void _initAgent() {
    if (_settings == null) return;
    final extra = buildGithubAgentExtraPrompt(
      owner: _ownerCtrl.text.trim(),
      repo: _repoCtrl.text.trim(),
    );
    _agent = ReasoningAgent(baseSettings: _settings, extraSystemPrompt: extra);
    _messages.clear();
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

    setState(() {
      _messages.add(Message(text: q, isUser: true));
      _queryCtrl.clear();
      _sending = true;
      _mcpUsed = false;
    });

    _scrollToBottom();

    try {
      // Обновляем агент с актуальным extraPrompt на всякий случай
      _initAgent();
      final res = await _agent!.ask(q);
      final rr = res['result'] as ReasoningResult;

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
    } catch (e) {
      setState(() {
        _messages.add(Message(text: 'Ошибка: $e', isUser: false));
        _sending = false;
        _mcpUsed = false;
      });
      _scrollToBottom();
    }
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
