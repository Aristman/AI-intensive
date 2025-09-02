import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/agents/auto_fix/auto_fix_agent.dart';
import 'package:sample_app/models/app_settings.dart';

void main() {
  group('AutoFixAgent', () {
    test('capabilities and ask()', () async {
      final agent = AutoFixAgent(initialSettings: const AppSettings());
      expect(agent.capabilities.streaming, isTrue);
      expect(agent.capabilities.stateful, isFalse);

      final r = await agent.ask(const AgentRequest('hello'));
      expect(r.isFinal, isTrue);
      expect(r.text, contains('AutoFixAgent'));
      agent.dispose();
    });

    test('start() emits minimal pipeline events', () async {
      final agent = AutoFixAgent(initialSettings: const AppSettings());
      final events = <AgentEvent>[];
      final sub = agent
          .start(const AgentRequest('analyze',
              context: {'path': 'x.dart', 'mode': 'file'}))
          .listen(events.add);
      await sub.asFuture<void>();
      expect(
          events.map((e) => e.stage),
          containsAll(<AgentStage>[
            AgentStage.analysis_started,
            AgentStage.analysis_result,
            AgentStage.pipeline_complete,
          ]));
      agent.dispose();
    });
  });
}
