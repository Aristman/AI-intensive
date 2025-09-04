import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/agents/auto_fix/auto_fix_agent.dart';
import 'package:sample_app/agents/code_ops_builder_agent.dart';

void main() {
  group('AutoFixAgent auth/rate-limit integration', () {
    test('ask() respects rate limit (>=2 within 1 minute throws)', () async {
      final agent = AutoFixAgent();
      // 1 запрос в минуту
      agent.updateAuthPolicy(limits: const AgentLimits(requestsPerMinute: 1));

      // Первый — ок
      final r1 = await agent.ask(const AgentRequest('hi'));
      expect(r1.isFinal, isTrue);

      // Второй — должен бросить StateError из ensureAuthorized
      expect(
        () => agent.ask(const AgentRequest('again')),
        throwsA(isA<StateError>()),
      );
    });

    test('start() second run within limit window yields pipeline_error', () async {
      final agent = AutoFixAgent();
      agent.updateAuthPolicy(limits: const AgentLimits(requestsPerMinute: 1));

      // Первый запуск пайплайна — ок
      final evts1 = await agent.start(const AgentRequest('go')).toList();
      expect(evts1.isNotEmpty, isTrue);
      expect(evts1.first.stage, AgentStage.pipeline_start);

      // Второй запуск сразу — превысит лимит; агент должен эмитить pipeline_error
      final evts2 = await agent.start(const AgentRequest('go2')).toList();
      expect(evts2.isNotEmpty, isTrue);
      expect(evts2.last.stage, AgentStage.pipeline_error);
      expect(evts2.last.severity, AgentSeverity.error);
      expect(evts2.last.meta?['action'], 'start');
    });

    test('ensureAuthorized with requiredRole=user passes after token auth', () async {
      final agent = AutoFixAgent();
      await agent.authenticate('token'); // поднимет роль до user
      await agent.ensureAuthorized(const AgentRequest('x'), action: 'ask', requiredRole: AgentRoles.user);
    });
  });

  group('CodeOpsBuilderAgent auth/rate-limit integration', () {
    test('start() rate limit triggers pipeline_error on repeated start', () async {
      final agent = CodeOpsBuilderAgent();
      agent.updateAuthPolicy(limits: const AgentLimits(requestsPerMinute: 1));

      final s1 = agent.start(const AgentRequest('run tests'))!;
      final evts1 = await s1.toList();
      expect(evts1.isNotEmpty, isTrue);
      // Первый запуск не должен начинаться с pipeline_error
      expect(evts1.first.stage, isNot(equals(AgentStage.pipeline_error)));

      final s2 = agent.start(const AgentRequest('run tests again'))!;
      final evts2 = await s2.toList();
      expect(evts2.isNotEmpty, isTrue);
      expect(evts2.last.stage, AgentStage.pipeline_error);
      expect(evts2.last.severity, AgentSeverity.error);
      expect(evts2.last.meta?['action'], 'start');
    });

    test('ensureAuthorized with requiredRole=admin fails for user, then passes after role update', () async {
      final agent = CodeOpsBuilderAgent();
      await agent.authenticate('t'); // role=user
      expect(
        () => agent.ensureAuthorized(const AgentRequest('x'), action: 'ask', requiredRole: AgentRoles.admin),
        throwsA(isA<StateError>()),
      );
      agent.updateAuthPolicy(role: AgentRoles.admin);
      await agent.ensureAuthorized(const AgentRequest('x'), action: 'ask', requiredRole: AgentRoles.admin);
    });
  });
}
