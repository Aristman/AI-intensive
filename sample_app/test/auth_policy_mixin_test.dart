import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';

class _DummyAgent with AuthPolicyMixin implements IAgent {
  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        stateful: false,
        streaming: false,
        reasoning: false,
      );

  @override
  Future<AgentResponse> ask(AgentRequest req) async {
    await ensureAuthorized(req, action: 'ask');
    return const AgentResponse(text: 'ok', isFinal: true);
  }

  @override
  Stream<AgentEvent>? start(AgentRequest req) => null;

  @override
  void dispose() {}

  @override
  void updateSettings(AppSettings settings) {}
}

class _DummyStreamingAgent with AuthPolicyMixin implements IAgent {
  final String? requiredRoleForStart;
  _DummyStreamingAgent({this.requiredRoleForStart});

  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        stateful: false,
        streaming: true,
        reasoning: false,
      );

  @override
  Future<AgentResponse> ask(AgentRequest req) async {
    await ensureAuthorized(req, action: 'ask', requiredRole: requiredRoleForStart);
    return const AgentResponse(text: 'ok', isFinal: true);
  }

  @override
  Stream<AgentEvent>? start(AgentRequest req) async* {
    try {
      await ensureAuthorized(req, action: 'start', requiredRole: requiredRoleForStart);
      yield AgentEvent(
        id: 'evt1',
        runId: 'run1',
        stage: AgentStage.pipeline_start,
        message: 'started',
      );
    } catch (e) {
      yield AgentEvent(
        id: 'auth-error',
        runId: 'run1',
        stage: AgentStage.pipeline_error,
        severity: AgentSeverity.error,
        message: 'Authorization error: $e',
        meta: {'action': 'start'},
      );
    }
  }

  @override
  void dispose() {}

  @override
  void updateSettings(AppSettings settings) {}
}

void main() {
  group('AuthPolicyMixin basics', () {
    test('authenticate without token → guest, authed=true', () async {
      final a = _DummyAgent();
      expect(a.role, 'guest');
      expect(a.isAuthenticated, isFalse);
      final ok = await a.authenticate(null);
      expect(ok, isTrue);
      expect(a.isAuthenticated, isTrue);
      expect(a.role, 'guest');
    });

    test('authenticate with token elevates role to user', () async {
      final a = _DummyAgent();
      await a.authenticate('token123');
      expect(a.isAuthenticated, isTrue);
      expect(a.role, 'user');
    });

    test('AgentRoles rank/allows hierarchy works', () {
      expect(AgentRoles.rank(AgentRoles.guest), 1);
      expect(AgentRoles.rank(AgentRoles.user), 2);
      expect(AgentRoles.rank(AgentRoles.admin), 3);
      expect(AgentRoles.allows('admin', 'user'), isTrue);
      expect(AgentRoles.allows('user', 'admin'), isFalse);
      expect(AgentRoles.allows('guest', null), isTrue);
    });

    test('ensureAuthorized with requiredRole throws if insufficient', () async {
      final a = _DummyAgent();
      await a.authenticate('userToken'); // user
      expect(a.role, 'user');
      // required admin should fail
      expect(
        () => a.ensureAuthorized(const AgentRequest('x'), action: 'ask', requiredRole: AgentRoles.admin),
        throwsA(isA<StateError>()),
      );
      // elevate to admin via policy update and check success
      a.updateAuthPolicy(role: AgentRoles.admin);
      await a.ensureAuthorized(const AgentRequest('x'), action: 'ask', requiredRole: AgentRoles.admin);
    });

    test('rate limit: allow N then block', () async {
      final a = _DummyAgent();
      a.updateAuthPolicy(limits: const AgentLimits(requestsPerHour: 3));
      // 3 allowed
      await a.ensureAuthorized(const AgentRequest('1'), action: 'ask');
      await a.ensureAuthorized(const AgentRequest('2'), action: 'ask');
      await a.ensureAuthorized(const AgentRequest('3'), action: 'ask');
      // 4th should fail
      expect(
        () => a.ensureAuthorized(const AgentRequest('4'), action: 'ask'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Streaming behavior on auth failure', () {
    test('start() yields pipeline_error when role insufficient', () async {
      final a = _DummyStreamingAgent(requiredRoleForStart: AgentRoles.admin);
      await a.authenticate('userToken'); // role=user
      final events = await a.start(const AgentRequest('go'))!.toList();
      expect(events.isNotEmpty, isTrue);
      final last = events.last;
      expect(last.stage, AgentStage.pipeline_error);
      expect(last.severity, AgentSeverity.error);
      expect(last.meta?['action'], 'start');
    });

    test('start() succeeds when role sufficient', () async {
      final a = _DummyStreamingAgent(requiredRoleForStart: AgentRoles.user);
      await a.authenticate('t');
      final first = await a.start(const AgentRequest('go'))!.first;
      expect(first.stage, AgentStage.pipeline_start);
    });
  });
}
