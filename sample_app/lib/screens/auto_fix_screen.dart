import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/agents/auto_fix/auto_fix_agent.dart';
import 'package:sample_app/services/patch_apply_service.dart';
import 'package:sample_app/utils/diff_view_utils.dart';

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
  bool _eventsExpanded =
      false; // панель событий: развернута во время выполнения
  List<Map<String, dynamic>> _patches = const [];
  final _patchService = PatchApplyService();
  // Всегда применяем через LLM-агента в PatchApplyService

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
      _eventsExpanded = true; // разворачиваем во время пайплайна
      _patches = const [];
      _events.add(AgentEvent(
        id: 'llm_analysis_start_${DateTime.now().millisecondsSinceEpoch}',
        runId: 'ui',
        stage: AgentStage.analysis_started,
        severity: AgentSeverity.info,
        message: 'Запрос к LLM: анализ кода',
        meta: {
          'path': path,
          'mode': _mode,
        },
      ));
    });

    final stream = _agent!.start(AgentRequest(
      'analyze',
      context: {
        // Передаём пустую строку, если путь не задан, чтобы агент не пытался
        // анализировать фиктивное значение и мог выдать корректное предупреждение.
        'path': path.isEmpty ? '' : path,
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
        // Оставляем панель событий развёрнутой
        _events.add(AgentEvent(
          id: 'llm_analysis_done_${DateTime.now().millisecondsSinceEpoch}',
          runId: 'ui',
          stage: AgentStage.analysis_result,
          severity: AgentSeverity.info,
          message: 'Запрос к LLM: анализ завершён',
        ));
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
                  ButtonSegment(
                      value: 'file',
                      label: Text('Файл'),
                      icon: Icon(Icons.insert_drive_file_outlined)),
                  ButtonSegment(
                      value: 'dir',
                      label: Text('Папка'),
                      icon: Icon(Icons.folder_open)),
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
          // Кнопки применения и отката
          Row(
            children: [
              ElevatedButton.icon(
                key: const Key('autofix_apply_btn'),
                onPressed: _patches.isEmpty || _running
                    ? null
                    : () async {
                        setState(() {
                          _running = true;
                          _eventsExpanded = true;
                          _events.add(AgentEvent(
                            id: 'llm_apply_start_${DateTime.now().millisecondsSinceEpoch}',
                            runId: 'ui',
                            stage: AgentStage.code_generation_started,
                            severity: AgentSeverity.info,
                            message: 'Запрос к LLM: применение диффа (старт)',
                            meta: {'patches': _patches.length},
                          ));
                        });

                        final count = await _patchService.applyPatches(
                          _patches,
                          settings: _settings,
                        );
                        if (mounted) {
                          setState(() {
                            _running = false;
                            _events.add(AgentEvent(
                              id: 'llm_apply_done_${DateTime.now().millisecondsSinceEpoch}',
                              runId: 'ui',
                              stage: AgentStage.code_generated,
                              severity: AgentSeverity.info,
                              message:
                                  'Применено файлов: $count (через LLM-агента)',
                              meta: {
                                'applied': count,
                                'patches': _patches.length,
                              },
                            ));
                          });
                        }
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
          const SizedBox(height: 8),
          const SizedBox(height: 16),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: Key('autofix_events_tile_${_eventsExpanded ? 1 : 0}'),
              initiallyExpanded: _eventsExpanded,
              onExpansionChanged: (v) => setState(() => _eventsExpanded = v),
              tilePadding: EdgeInsets.zero,
              title: Text('События',
                  style: Theme.of(context).textTheme.titleMedium),
              children: [
                SizedBox(
                  height: 200,
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
                                : (e.severity == AgentSeverity.warning
                                    ? Icons.warning_amber_outlined
                                    : Icons.info_outline),
                          ),
                          title: Text('${e.stage.name}: ${e.message}'),
                          subtitle:
                              e.meta == null ? null : Text(e.meta.toString()),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_patches.isNotEmpty) ...[
            Text(
              'Предпросмотр диффа',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              key: const Key('autofix_diff_container'),
              height: 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _DiffPreview(
                    diffText: _patches
                        .map((p) => (p['diff'] as String?) ?? '')
                        .where((d) => d.isNotEmpty)
                        .join('\n\n'),
                  ),
                ),
              ),
            ),
          ],
          // Убрали отдельный предпросмотр LLM raw: теперь все изменения отображаются в общем предпросмотре
        ],
      ),
    );
  }
}

class _DiffPreview extends StatelessWidget {
  final String diffText;
  const _DiffPreview({required this.diffText});

  Color _bgForLine(BuildContext context, String line) {
    if (line.startsWith('+++') || line.startsWith('---')) {
      return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
    if (line.startsWith('+')) return Colors.green.withOpacity(0.08);
    if (line.startsWith('-')) return Colors.red.withOpacity(0.08);
    return Colors.transparent;
  }

  Color _fgForLine(BuildContext context, String line) {
    if (line.startsWith('+')) return Colors.green.shade800;
    if (line.startsWith('-')) return Colors.red.shade800;
    return Theme.of(context).colorScheme.onSurface;
  }

  @override
  Widget build(BuildContext context) {
    final sections = splitUnifiedDiffIntoSections(diffText);
    if (sections.isEmpty) {
      return const Center(child: Text('Нет данных diff'));
    }
    return ListView.builder(
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final s = sections[index];
        final isHunk = s.title.trim().startsWith('@@');
        final titleWidget = Text(
          s.title.isEmpty ? (isHunk ? '@@' : 'Header') : s.title,
          style: const TextStyle(
              fontFamily: 'monospace', fontWeight: FontWeight.w600),
        );

        final content = Container(
          decoration: BoxDecoration(
            border:
                Border(left: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: s.lines.length,
            itemBuilder: (context, i) {
              final line = s.lines[i];
              return Container(
                color: _bgForLine(context, line),
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(
                        line.isEmpty ? '' : line[0],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: _fgForLine(context, line),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line.length > 1 ? line.substring(1) : '',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: _fgForLine(context, line),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );

        if (isHunk) {
          return Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: index == 0,
              dense: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 8),
              childrenPadding:
                  const EdgeInsets.only(left: 8, right: 4, bottom: 8),
              title: titleWidget,
              children: [content],
            ),
          );
        }
        // Header section (no collapse)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: titleWidget,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 4, bottom: 8),
              child: content,
            ),
          ],
        );
      },
    );
  }
}
