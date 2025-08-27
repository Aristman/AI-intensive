import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/agents/auto_fix/auto_fix_agent.dart';
import 'package:sample_app/models/app_settings.dart';

void main() {
  group('AutoFixAgent token usage', () {
    test('emits llm_usage in events when llm_usage_override is provided', () async {
      final agent = AutoFixAgent(initialSettings: const AppSettings());

      // Подделываем LLM ответ и usage без реального вызова сети
      const fakeLlmText = '--- a/x.dart\n+++ b/x.dart\n@@ -1,1 +1,1 @@\n-old\n+new\n';
      final usage = {
        'provider': 'test-llm',
        'model': 'test-model',
        'promptTokens': 123,
        'completionTokens': 45,
        'totalTokens': 168,
      };

      final events = <AgentEvent>[];
      final stream = agent.start(AgentRequest(
        'analyze',
        context: {
          'path': '', // путь пустой, чтобы не искать реальные файлы
          'mode': 'file',
          'llm_raw_override': fakeLlmText,
          'llm_usage_override': usage,
        },
      ));

      expect(stream, isNotNull);
      final sub = stream.listen(events.add);
      await sub.asFuture<void>();

      // Должны получить хотя бы одно событие с meta.llm_usage
      final hasUsage = events.any((e) => e.meta is Map<String, dynamic> && (e.meta as Map<String, dynamic>).containsKey('llm_usage'));
      expect(hasUsage, isTrue);

      // В финальном событии pipeline_complete usage также должен присутствовать
      final complete = events.where((e) => e.stage == AgentStage.pipeline_complete).toList();
      expect(complete, isNotEmpty);
      final meta = complete.last.meta as Map<String, dynamic>?;
      expect(meta, isNotNull);
      expect(meta!['llm_usage'], isNotNull);
      final u = meta['llm_usage'] as Map<String, dynamic>;
      expect(u['provider'], equals('test-llm'));
      expect(u['model'], equals('test-model'));
      expect(u['promptTokens'], equals(123));
      expect(u['completionTokens'], equals(45));
      expect(u['totalTokens'], equals(168));

      agent.dispose();
    });
  });
}
