import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/agents/auto_fix/auto_fix_agent.dart';

void main() {
  group('AutoFixAgent LLM patches integration', () {
    Future<List<AgentEvent>> collectEvents(Stream<AgentEvent>? s) async {
      if (s == null) return [];
      final out = <AgentEvent>[];
      final c = Completer<void>();
      late final StreamSubscription sub;
      sub = s.listen(out.add, onDone: () {
        c.complete();
      }, onError: (e) {
        c.complete();
      });
      await c.future;
      await sub.cancel();
      return out;
    }

    test('includes llm_patches separately when includeLLMInApply=false', () async {
      final dir = await Directory.systemTemp.createTemp('autofix_agent_');
      final file = File('${dir.path}/main.dart');
      await file.writeAsString('void main(){}\n');

      final pathEsc = file.path.replaceAll('\\', '/');
      final raw = '--- a/$pathEsc\n'
          '+++ b/$pathEsc\n'
          '@@ -1,1 +1,1 @@\n'
          '-void main(){}\n'
          '+void main(){ print(\'hi\'); }\n';

      final agent = AutoFixAgent();
      final events = await collectEvents(agent.start(AgentRequest('analyze', context: {
        'path': file.path,
        'mode': 'file',
        'useLLM': true,
        'includeLLMInApply': false,
        'llm_raw_override': raw,
      })));

      final complete = events.where((e) => e.stage == AgentStage.pipeline_complete).toList();
      expect(complete.length, 1);
      final meta = complete.first.meta as Map<String, dynamic>?;
      expect(meta, isNotNull);
      final patches = meta!['patches'] ?? [];
      final llmPatches = meta['llm_patches'] ?? [];
      // базовые фиксы могут быть пустыми, нас интересует, что LLM патчи не включены в patches
      expect(llmPatches.length, 1);
      expect(patches.length, lessThanOrEqualTo(1));
    });

    test('merges llm_patches into patches when includeLLMInApply=true', () async {
      final dir = await Directory.systemTemp.createTemp('autofix_agent_');
      final file = File('${dir.path}/main.dart');
      await file.writeAsString('void main(){}\n');

      final pathEsc = file.path.replaceAll('\\', '/');
      final raw = '--- a/$pathEsc\n'
          '+++ b/$pathEsc\n'
          '@@ -1,1 +1,1 @@\n'
          '-void main(){}\n'
          '+void main(){ print(\'hi\'); }\n';

      final agent = AutoFixAgent();
      final events = await collectEvents(agent.start(AgentRequest('analyze', context: {
        'path': file.path,
        'mode': 'file',
        'useLLM': true,
        'includeLLMInApply': true,
        'llm_raw_override': raw,
      })));

      final complete = events.where((e) => e.stage == AgentStage.pipeline_complete).toList();
      expect(complete.length, 1);
      final meta = complete.first.meta as Map<String, dynamic>?;
      expect(meta, isNotNull);
      final patches = meta!['patches'] ?? [];
      final llmPatches = meta['llm_patches'] ?? [];
      expect(llmPatches.length, 1);
      expect(patches.length, greaterThanOrEqualTo(1)); // объединены
    });
  });
}
