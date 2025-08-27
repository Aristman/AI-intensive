import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/agents/auto_fix/auto_fix_agent.dart';
import 'package:sample_app/models/app_settings.dart';

void main() {
  test('AutoFixAgent: useLLM=true не ломает пайплайн и даёт warning при отсутствии ключей', () async {
    final tmp = await Directory.systemTemp.createTemp('autofix_llm_');
    final file = File('${tmp.path}/a.dart');
    await file.writeAsString('void main() {  }  '); // хвостовые пробелы + нет финальной новой строки

    final agent = AutoFixAgent(initialSettings: const AppSettings());

    final events = <AgentEvent>[];
    final stream = agent.start(AgentRequest('analyze', context: {
      'path': file.path,
      'mode': 'file',
      'useLLM': true, // включаем LLM этап
    }));

    final done = Completer<void>();
    final sub = stream.listen((e) {
      events.add(e);
      if (e.stage == AgentStage.pipeline_complete || e.stage == AgentStage.pipeline_error) {
        done.complete();
      }
    });

    await done.future.timeout(const Duration(seconds: 8));
    await sub.cancel();

    // Пайплайн завершается
    final completed = events.where((e) => e.stage == AgentStage.pipeline_complete).toList();
    expect(completed.isNotEmpty, true, reason: 'pipeline_complete должен быть');

    // Допускаем два исхода: либо пришёл llm_raw, либо warning об отсутствии LLM
    final hasLlmRaw = events.any((e) => (e.meta ?? const {})['llm_raw'] != null);
    final llmWarn = events.where((e) => e.stage == AgentStage.analysis_result && e.severity == AgentSeverity.warning)
        .any((e) => e.message.contains('LLM'));
    expect(hasLlmRaw || llmWarn, true, reason: 'Ожидаем либо llm_raw, либо warning об LLM');

    // Есть патчи от базового анализатора
    final last = completed.last;
    final patches = (last.meta?['patches'] is List)
        ? List<Map<String, dynamic>>.from(last.meta?['patches'] as List)
        : <Map<String, dynamic>>[];
    expect(patches.isNotEmpty, true, reason: 'Должен быть хотя бы один патч');

    await tmp.delete(recursive: true);
  });

  test('AutoFixAgent: useLLM=false — нет llm_raw в событиях', () async {
    final tmp = await Directory.systemTemp.createTemp('autofix_llm_off_');
    final file = File('${tmp.path}/b.dart');
    await file.writeAsString('void main() {}');

    final agent = AutoFixAgent(initialSettings: const AppSettings());

    final events = <AgentEvent>[];
    final stream = agent.start(AgentRequest('analyze', context: {
      'path': file.path,
      'mode': 'file',
      'useLLM': false,
    }));

    final done = Completer<void>();
    final sub = stream.listen((e) {
      events.add(e);
      if (e.stage == AgentStage.pipeline_complete || e.stage == AgentStage.pipeline_error) {
        done.complete();
      }
    });

    await done.future.timeout(const Duration(seconds: 8));
    await sub.cancel();

    final hasLlmRaw = events.any((e) => (e.meta ?? const {})['llm_raw'] != null);
    expect(hasLlmRaw, false, reason: 'При useLLM=false не должно быть llm_raw');

    await tmp.delete(recursive: true);
  });
}
