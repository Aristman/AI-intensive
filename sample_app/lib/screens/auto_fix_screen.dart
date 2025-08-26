import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/agents/auto_fix/auto_fix_agent.dart';

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

  IAgent? _agent;
  StreamSubscription<AgentEvent>? _sub;
  final List<AgentEvent> _events = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
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
    });

    final stream = _agent!.start(AgentRequest(
      'analyze',
      context: {
        'path': path.isEmpty ? '(none)' : path,
        'mode': _mode,
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
              ElevatedButton.icon(
                key: const Key('autofix_analyze_btn'),
                onPressed: _running ? null : _runAnalysis,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Анализ'),
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
        ],
      ),
    );
  }
}
