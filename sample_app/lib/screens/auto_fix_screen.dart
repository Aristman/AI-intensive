import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/agents/auto_fix/auto_fix_agent.dart';
import 'package:sample_app/agents/code_audit_agent.dart';
import 'package:sample_app/services/patch_apply_service.dart';
import 'package:sample_app/utils/diff_view_utils.dart';

class AutoFixScreen extends StatefulWidget {
  const AutoFixScreen({super.key});

  @override
  State<AutoFixScreen> createState() => _AutoFixScreenState();
}

class _AuditPrettyView extends StatelessWidget {
  final Map<String, dynamic> result;
  const _AuditPrettyView({required this.result});

  @override
  Widget build(BuildContext context) {
    final summary = (result['summary'] as String?)?.trim() ?? '';
    final files = (result['files'] as List?)?.cast<Map>() ?? const [];
    final filteredFiles = files
        .where((m) {
          final map = Map<String, dynamic>.from(m as Map);
          final problems = (map['problems'] as List?)?.cast<String>() ?? const [];
          final suggestions = (map['suggestions'] as List?)?.cast<String>() ?? const [];
          return problems.isNotEmpty || suggestions.isNotEmpty;
        })
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList(growable: false);
    final projectSuggestions = (result['project_suggestions'] as List?)?.cast<String>() ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.isNotEmpty) ...[
          Text('Итоговый обзор', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          _CardBlock(
            child: Text(summary),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            _StatChip(icon: Icons.find_in_page_outlined, label: 'Файлов с находками', value: filteredFiles.length.toString()),
            const SizedBox(width: 8),
            _StatChip(icon: Icons.lightbulb_outline, label: 'Проектные рекомендации', value: projectSuggestions.length.toString()),
          ],
        ),
        const SizedBox(height: 12),
        if (projectSuggestions.isNotEmpty) ...[
          Text('Рекомендации по проекту', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          _CardBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in projectSuggestions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(child: Text(s)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text('Файлы с находками (проблемы/рекомендации)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        if (filteredFiles.isEmpty)
          _CardBlock(child: const Text('В проанализированных файлах не найдено проблем или рекомендаций.'))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredFiles.length,
            itemBuilder: (context, index) {
              final f = filteredFiles[index];
              final file = (f['file'] as String?) ?? 'unknown';
              final suggestions = (f['suggestions'] as List?)?.cast<String>() ?? const [];
              final problems = (f['problems'] as List?)?.cast<String>() ?? const [];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _FileAuditCard(
                  file: file,
                  suggestions: suggestions,
                  problems: problems,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _CardBlock extends StatelessWidget {
  final Widget child;
  const _CardBlock({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: child,
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$label: $value'),
    );
  }
}

class _FileAuditCard extends StatelessWidget {
  final String file;
  final List<String> suggestions;
  final List<String> problems;
  const _FileAuditCard({required this.file, required this.suggestions, required this.problems});

  @override
  Widget build(BuildContext context) {
    return _CardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  file,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (problems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                const SizedBox(width: 6),
                const Text('Проблемы', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            for (final p in problems)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(p)),
                  ],
                ),
              ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: const [
                Icon(Icons.tips_and_updates_outlined, size: 18),
                SizedBox(width: 6),
                Text('Предложения', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            for (final s in suggestions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(s)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AutoFixScreenState extends State<AutoFixScreen> {
  final _settingsService = SettingsService();
  AppSettings? _settings;
  bool _loading = true;

  final _pathCtrl = TextEditingController();
  String _mode = 'file'; // 'file' | 'dir'

  IAgent? _agent;
  IAgent? _auditAgent;
  StreamSubscription<AgentEvent>? _sub;
  final List<AgentEvent> _events = [];
  bool _running = false;
  bool _eventsExpanded =
      true; // панель событий: по умолчанию развёрнута для видимости списка в тестах
  List<Map<String, dynamic>> _patches = const [];
  final _patchService = PatchApplyService();
  // Всегда применяем через LLM-агента в PatchApplyService

  String _auditJson = '';
  bool _auditExpanded = true;
  Map<String, dynamic>? _auditResult; // распарсенный JSON результата аудита

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
      _auditAgent = CodeAuditAgent(initialSettings: s);
      _loading = false;
    });
  }

  Map<String, dynamic>? _safeParseAuditJson(String text) {
    try {
      final decoded = json.decode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _agent?.dispose();
    _auditAgent?.dispose();
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

  Future<void> _runProjectAudit() async {
    if (_auditAgent == null) return;
    final path = _pathCtrl.text.trim();
    setState(() {
      _events.clear();
      _running = true;
      _eventsExpanded = true;
      _auditJson = '';
      _events.add(AgentEvent(
        id: 'audit_start_${DateTime.now().millisecondsSinceEpoch}',
        runId: 'ui',
        stage: AgentStage.analysis_started,
        severity: AgentSeverity.info,
        message: 'Аудит проекта (офлайн, лимит 20 файлов)',
        meta: {
          'path': path,
          'mode': _mode,
        },
      ));
    });

    final stream = _auditAgent!.start(AgentRequest('audit', context: {
      'path': path.isEmpty ? '' : path,
    }));

    if (stream == null) {
      setState(() => _running = false);
      return;
    }

    _sub?.cancel();
    _sub = stream.listen((e) {
      setState(() {
        _events.add(e);
        if (e.stage == AgentStage.analysis_result) {
          final m = e.meta;
          final txt = (m != null ? m['jsonText'] as String? : null) ?? '';
          _auditJson = txt;
          _auditResult = _safeParseAuditJson(txt);
        }
      });
    }, onError: (e) {
      setState(() {
        _running = false;
        _events.add(AgentEvent(
          id: 'audit_err',
          runId: 'unknown',
          stage: AgentStage.pipeline_error,
          severity: AgentSeverity.error,
          message: 'Ошибка: $e',
        ));
      });
    }, onDone: () {
      setState(() {
        _running = false;
        _events.add(AgentEvent(
          id: 'audit_done_${DateTime.now().millisecondsSinceEpoch}',
          runId: 'ui',
          stage: AgentStage.pipeline_complete,
          severity: AgentSeverity.info,
          message: 'Аудит завершён',
        ));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
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
              Tooltip(
                message: 'Выбрать файл',
                child: OutlinedButton.icon(
                key: const Key('autofix_pick_file_btn'),
                onPressed: () async {
                        FocusScope.of(context).unfocus();
                        try {
                          debugPrint('[AutoFix] File button clicked');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Открываю диалог выбора файла...')),
                            );
                          }
                          // Диалог выбора файла
                          final file = await openFile();
                          if (file != null) {
                            setState(() {
                              _mode = 'file';
                              _pathCtrl.text = file.path;
                              // Сброс результата аудита при выборе нового проекта/файла
                              _auditJson = '';
                              _auditResult = null;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Файл выбран: ${file.name}')),
                              );
                            }
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Выбор файла отменён')),
                              );
                            }
                          }
                        } catch (e) {
                          debugPrint('[AutoFix] openFile error: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Ошибка открытия диалога файла: $e')),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.insert_drive_file_outlined),
                label: const Text('Файл'),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Выбрать папку проекта',
                child: OutlinedButton.icon(
                key: const Key('autofix_pick_project_btn'),
                onPressed: () async {
                        FocusScope.of(context).unfocus();
                        try {
                          debugPrint('[AutoFix] Project button clicked');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Открываю диалог выбора папки...')),
                            );
                          }
                          // Диалог выбора папки (проекта)
                          final dirPath = await getDirectoryPath(
                            confirmButtonText: 'Выбрать',
                          );
                          if (dirPath != null && dirPath.isNotEmpty) {
                            setState(() {
                              _mode = 'dir';
                              _pathCtrl.text = dirPath;
                              // Сброс результата аудита при выборе нового проекта
                              _auditJson = '';
                              _auditResult = null;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Папка выбрана: $dirPath')),
                              );
                            }
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Выбор папки отменён')),
                              );
                            }
                          }
                        } catch (e) {
                          debugPrint('[AutoFix] getDirectoryPath error: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Ошибка открытия диалога папки: $e')),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.folder_open),
                label: const Text('Проект'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: const Key('autofix_analyze_btn'),
                onPressed: _running ? null : _runAnalysis,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Анализ'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: const Key('audit_project_btn'),
                onPressed: _running ? null : _runProjectAudit,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Аудит проекта'),
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
                        if (!context.mounted) return;
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
                        if (!context.mounted) return;
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
                        final stageAndMsg = '${e.stage.name}: ${e.message}';
                        final metaStr = e.meta == null
                            ? null
                            : const JsonEncoder.withIndent('  ').convert(e.meta);
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            e.severity == AgentSeverity.error
                                ? Icons.error_outline
                                : (e.severity == AgentSeverity.warning
                                    ? Icons.warning_amber_outlined
                                    : Icons.info_outline),
                          ),
                          title: SelectableText(stageAndMsg),
                          subtitle: metaStr == null ? null : SelectableText(metaStr),
                          trailing: IconButton(
                            tooltip: 'Копировать',
                            icon: const Icon(Icons.copy_all_outlined),
                            onPressed: () async {
                              final buf = StringBuffer(stageAndMsg);
                              if (metaStr != null) {
                                buf.writeln();
                                buf.write(metaStr);
                              }
                              await Clipboard.setData(ClipboardData(text: buf.toString()));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Скопировано в буфер обмена')),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Результат аудита
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: Key('audit_json_tile_${_auditExpanded ? 1 : 0}'),
              initiallyExpanded: _auditExpanded,
              onExpansionChanged: (v) => setState(() => _auditExpanded = v),
              tilePadding: EdgeInsets.zero,
              title: Text('Результат аудита',
                  style: Theme.of(context).textTheme.titleMedium),
              children: [
                Row(
                  children: [
                    OutlinedButton.icon(
                      key: const Key('audit_copy_btn'),
                      onPressed: _auditJson.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(text: _auditJson));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('JSON скопирован в буфер обмена')),
                              );
                            },
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Скопировать'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const Key('audit_save_btn'),
                      onPressed: _auditJson.isEmpty
                          ? null
                          : () async {
                              try {
                                final location = await getSaveLocation(
                                  suggestedName: 'code_audit_result.json',
                                  confirmButtonText: 'Сохранить',
                                );
                                if (location != null && location.path.isNotEmpty) {
                                  final file = File(location.path);
                                  await file.writeAsString(_auditJson);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Сохранено: ${location.path}')),
                                  );
                                }
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка сохранения: $e')),
                                );
                              }
                            },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Сохранить'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_auditResult != null)
                  _AuditPrettyView(result: _auditResult!)
                else if (_auditJson.isNotEmpty)
                  SizedBox(
                    height: 160,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(8),
                        child: SelectableText(
                          _auditJson,
                          key: const Key('audit_json_text'),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
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
    if (line.startsWith('+')) return Colors.green.withValues(alpha: 0.08);
    if (line.startsWith('-')) return Colors.red.withValues(alpha: 0.08);
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
