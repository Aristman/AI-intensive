import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/agents/multi_step_reasoning_agent.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/services/auth_service.dart';

class ReasoningAgentScreen extends StatefulWidget {
  const ReasoningAgentScreen({super.key});

  @override
  State<ReasoningAgentScreen> createState() => _ReasoningAgentScreenState();
}

class _ReasoningAgentScreenState extends State<ReasoningAgentScreen> {
  final TextEditingController _controller = TextEditingController();
  final SettingsService _settingsService = SettingsService();
  AppSettings? _settings;

  MultiStepReasoningAgent? _agent;
  StreamSubscription<AgentEvent>? _sub;

  // UI state
  bool _busy = false;
  final List<AgentEvent> _events = [];
  String _finalMd = '';
  bool _mcpUsed = false;
  final AuthService _auth = AuthService();

  static const String _conversationKey = 'multi_step_reasoning_screen';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // Следим за изменениями глобальной аутентификации
    _auth.addListener(_onAuthChanged);
  }

  Future<void> _loadSettings() async {
    final s = await _settingsService.getSettings();
    setState(() => _settings = s);
    _agent = MultiStepReasoningAgent(settings: s, conversationKey: _conversationKey);
    // Устанавливаем режим в зависимости от глобального токена
    final token = _auth.token;
    if (token == null || token.isEmpty) {
      _agent!.setGuest();
      await _agent!.authenticate(null);
    } else {
      await _agent!.authenticate(token);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    _agent?.dispose();
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  Future<void> _run() async {
    final txt = _controller.text.trim();
    if (txt.isEmpty || _busy || _agent == null || _settings == null) return;

    setState(() {
      _busy = true;
      _events.clear();
      _finalMd = '';
      _mcpUsed = false;
    });

    final req = AgentRequest(
      txt,
      timeout: const Duration(seconds: 30),
      authToken: _auth.token,
    );
    final stream = _agent!.start(req);
    _sub?.cancel();
    _sub = stream?.listen((e) {
      setState(() {
        _events.add(e);
        if (e.stage == AgentStage.pipeline_complete) {
          _finalMd = (e.meta?['finalText'] as String?) ?? '';
          _mcpUsed = (e.meta?['mcpUsed'] as bool?) ?? false;
        }
      });
    }, onError: (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _events.add(AgentEvent(
          id: 'error',
          runId: 'error',
          stage: AgentStage.pipeline_error,
          message: 'Ошибка: $err',
        ));
      });
    }, onDone: () {
      if (!mounted) return;
      setState(() => _busy = false);
    });
  }

  void _cancel() {
    _sub?.cancel();
    setState(() => _busy = false);
  }

  Future<void> _onAuthChanged() async {
    if (_agent == null) return;
    final token = _auth.token;
    if (token == null || token.isEmpty) {
      _agent!.setGuest();
      await _agent!.authenticate(null);
    } else {
      await _agent!.authenticate(token);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_mcpUsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: 'MCP: использован поиск',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_done, color: Theme.of(context).colorScheme.tertiary),
                      const SizedBox(width: 8),
                      Text(
                        'MCP использован',
                        style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Ваш запрос',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _run(),
                  ),
                ),
                const SizedBox(width: 8),
                _busy
                    ? IconButton(
                        tooltip: 'Отменить',
                        onPressed: _cancel,
                        icon: const Icon(Icons.stop_circle_outlined),
                      )
                    : IconButton(
                        tooltip: 'Отправить',
                        onPressed: _run,
                        icon: const Icon(Icons.send),
                      ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                // Левая колонка — этапы
                Expanded(
                  flex: 1,
                  child: _buildStages(),
                ),
                // Правая колонка — финальный ответ (Markdown)
                Expanded(
                  flex: 1,
                  child: _buildFinal(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStages() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: const Text('Этапы выполнения', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, i) {
                final e = _events[i];
                return ListTile(
                  leading: _stageIcon(e.stage),
                  title: Text(e.message),
                  subtitle: e.meta == null ? null : Text(_shorten(e.meta.toString())),
                  dense: true,
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: _events.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinal() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: const Text('Финальный ответ (Markdown)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: _finalMd.isEmpty
                ? const Center(child: Text('Ответ появится здесь'))
                : Markdown(
                    data: _finalMd,
                    selectable: true,
                    padding: const EdgeInsets.all(12),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _stageIcon(AgentStage s) {
    switch (s) {
      case AgentStage.pipeline_start:
        return const Icon(Icons.play_arrow);
      case AgentStage.analysis_started:
        return const Icon(Icons.psychology);
      case AgentStage.analysis_result:
        return const Icon(Icons.psychology_alt_outlined);
      case AgentStage.docker_exec_started:
        return const Icon(Icons.playlist_play);
      case AgentStage.docker_exec_result:
        return const Icon(Icons.playlist_add_check_circle_outlined);
      case AgentStage.refine_tests_started:
        return const Icon(Icons.verified_outlined);
      case AgentStage.refine_tests_result:
        return const Icon(Icons.verified);
      case AgentStage.test_generation_started:
        return const Icon(Icons.description_outlined);
      case AgentStage.code_generation_started:
        return const Icon(Icons.loop);
      case AgentStage.pipeline_complete:
        return const Icon(Icons.check_circle_outline);
      case AgentStage.pipeline_error:
        return const Icon(Icons.error_outline);
      default:
        return const Icon(Icons.info_outline);
    }
  }

  String _shorten(String s, {int max = 240}) {
    if (s.length <= max) return s;
    return s.substring(0, max) + '…';
  }
}
