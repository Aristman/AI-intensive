import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/agents/auto_fix/auto_fix_agent.dart';
import 'package:sample_app/services/patch_apply_service.dart';

class AutoFixScreen extends StatefulWidget {
  const AutoFixScreen({super.key});

  @override
  State<AutoFixScreen> createState() => _AutoFixScreenState();
}

class _AutoFixScreenState extends State<AutoFixScreen> {
  final _settingsService = SettingsService();
  AppSettings? _settings;
  bool _loading = true;

  final _pathCtrl = TextEditingController();
  String _mode = 'file'; // 'file' | 'dir'
  bool _useLlm = false; // М2: включать ли LLM этап
  bool _includeLlmInApply = false; // включать ли LLM патчи в Apply

  IAgent? _agent;
  StreamSubscription<AgentEvent>? _sub;
  final List<AgentEvent> _events = [];
  bool _running = false;
  List<Map<String, dynamic>> _patches = const [];
  final _patchService = PatchApplyService();
  String? _llmRaw; // предпросмотр ответа LLM

  @override
  void initState() {
    super.initState();
    _pathCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    final s = await _settingsService.getSettings();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _agent = AutoFixAgent(initialSettings: s);
      _loading = false;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _agent?.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAnalysis() async {
    if (_agent == null) return;
    final path = _pathCtrl.text.trim();
    setState(() {
      _events.clear();
      _running = true;
      _patches = const [];
      _llmRaw = null;
    });

    final stream = _agent!.start(AgentRequest(
      'analyze',
      context: {
        // Передаём пустую строку, если путь не задан, чтобы агент не пытался
        // анализировать фиктивное значение и мог выдать корректное предупреждение.
        'path': path.isEmpty ? '' : path,
        'mode': _mode,
        'useLLM': _useLlm,
        'includeLLMInApply': _includeLlmInApply,
      },
    ));

    if (stream == null) {
      setState(() => _running = false);
      return;
    }

    _sub?.cancel();
    _sub = stream.listen((e) {
      setState(() {
        _events.add(e);
        // LLM предложения как отдельное событие analysis_result с meta.llm_raw
        final meta = e.meta ?? const {};
        if (meta is Map && meta['llm_raw'] is String) {
          _llmRaw = meta['llm_raw'] as String;
        }
        if (e.stage == AgentStage.pipeline_complete) {
          final m = e.meta;
          final patches = (m != null && m['patches'] is List)
              ? List<Map<String, dynamic>>.from(m['patches'] as List)
              : <Map<String, dynamic>>[];
          _patches = patches;
        }
      });
    }, onError: (e) {
      setState(() {
        _running = false;
        _events.add(AgentEvent(
          id: 'err',
          runId: 'unknown',
          stage: AgentStage.pipeline_error,
          severity: AgentSeverity.error,
          message: 'Ошибка: $e',
        ));
      });
    }, onDone: () {
      setState(() {
        _running = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('autofix_path_field'),
                  controller: _pathCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Путь к файлу или папке',
                    hintText: 'например: sample_app/lib/main.dart',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                key: const Key('autofix_mode_segmented'),
                segments: const [
                  ButtonSegment(value: 'file', label: Text('Файл'), icon: Icon(Icons.insert_drive_file_outlined)),
                  ButtonSegment(value: 'dir', label: Text('Папка'), icon: Icon(Icons.folder_open)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  const Text('LLM'),
                  Switch(
                    key: const Key('autofix_use_llm_switch'),
                    value: _useLlm,
                    onChanged: _running ? null : (v) => setState(() => _useLlm = v),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  const Text('Include LLM patches'),
                  Checkbox(
                    key: const Key('autofix_include_llm_checkbox'),
                    value: _includeLlmInApply,
                    onChanged: _running ? null : (v) => setState(() => _includeLlmInApply = v ?? false),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: const Key('autofix_analyze_btn'),
                onPressed: _running ? null : _runAnalysis,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Анализ'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Кнопки применения и отката
          Row(
            children: [
              ElevatedButton.icon(
                key: const Key('autofix_apply_btn'),
                onPressed: _patches.isEmpty || _running
                    ? null
                    : () async {
                        final count = await _patchService.applyPatches(_patches);
                        if (mounted) setState(() {});
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Применено файлов: $count')),
                        );
                      },
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Apply'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                key: const Key('autofix_rollback_btn'),
                onPressed: !_patchService.canRollback || _running
                    ? null
                    : () async {
                        final count = await _patchService.rollbackLast();
                        if (mounted) setState(() {});
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Откат файлов: $count')),
                        );
                      },
                icon: const Icon(Icons.undo),
                label: const Text('Rollback'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('События', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                key: const Key('autofix_events_list'),
                itemCount: _events.length,
                itemBuilder: (context, index) {
                  final e = _events[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      e.severity == AgentSeverity.error
                          ? Icons.error_outline
                          : (e.severity == AgentSeverity.warning ? Icons.warning_amber_outlined : Icons.info_outline),
                    ),
                    title: Text('${e.stage.name}: ${e.message}'),
                    subtitle: e.meta == null ? null : Text(e.meta.toString()),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_patches.isNotEmpty) ...[
            Text('Предпросмотр диффа (1 из ${_patches.length})', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              key: const Key('autofix_diff_container'),
              height: 220,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _patches.first['diff'] ?? '',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if ((_llmRaw ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('LLM предложения (предпросмотр)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              key: const Key('autofix_llm_container'),
              height: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _llmRaw!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
