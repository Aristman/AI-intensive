import 'package:test/test.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';

void main() {
  group('AgentRequest/AgentResponse DTOs', () {
    test('AgentRequest stores fields correctly', () {
      final req = AgentRequest(
        'Hello',
        timeout: const Duration(seconds: 5),
        context: {'k': 1},
        overrideFormat: ResponseFormat.json,
        overrideJsonSchema: '{"type":"object"}',
      );
      expect(req.input, 'Hello');
      expect(req.timeout, const Duration(seconds: 5));
      expect(req.context, containsPair('k', 1));
      expect(req.overrideFormat, ResponseFormat.json);
      expect(req.overrideJsonSchema, isNotNull);
    });

    test('AgentResponse defaults and fields', () {
      final res = AgentResponse(text: 'ok', isFinal: true);
      expect(res.text, 'ok');
      expect(res.isFinal, isTrue);
      expect(res.mcpUsed, isFalse);
      expect(res.uncertainty, isNull);
      expect(res.meta, isNull);
    });
  });

  group('AgentCapabilities', () {
    test('Capabilities store flags and tools', () {
      final caps = AgentCapabilities(
        stateful: true,
        streaming: false,
        reasoning: true,
        tools: {'docker_exec_java'},
      );
      expect(caps.stateful, isTrue);
      expect(caps.streaming, isFalse);
      expect(caps.reasoning, isTrue);
      expect(caps.tools, contains('docker_exec_java'));
    });
  });

  group('AgentTextUtils', () {
    test('extractUncertainty parses RU percent', () {
      final u = AgentTextUtils.extractUncertainty('Неопределенность: 27%');
      expect(u, closeTo(0.27, 1e-9));
    });

    test('extractUncertainty parses EN fraction', () {
      final u = AgentTextUtils.extractUncertainty('uncertainty: 0.07');
      expect(u, closeTo(0.07, 1e-9));
    });

    test('extractUncertainty parses EN with percent misplaced', () {
      final u = AgentTextUtils.extractUncertainty('15 % uncertainty about this');
      expect(u, closeTo(0.15, 1e-9));
    });

    test('extractUncertainty returns null when absent', () {
      final u = AgentTextUtils.extractUncertainty('no metric here');
      expect(u, isNull);
    });

    test('stripStopToken removes token and reports flag', () {
      final r = AgentTextUtils.stripStopToken('answer<<STOP>>', '<<STOP>>');
      expect(r.text, 'answer');
      expect(r.hadStop, isTrue);
    });

    test('stripStopToken leaves text when no token', () {
      final r = AgentTextUtils.stripStopToken('answer', '<<STOP>>');
      expect(r.text, 'answer');
      expect(r.hadStop, isFalse);
    });
  });

  group('AgentEvent & enums', () {
    test('AgentStage contains key pipeline stages', () {
      expect(AgentStage.values.contains(AgentStage.code_generated), isTrue);
      expect(AgentStage.values.contains(AgentStage.docker_exec_result), isTrue);
      expect(AgentStage.values.contains(AgentStage.pipeline_complete), isTrue);
      expect(AgentStage.values.contains(AgentStage.pipeline_error), isTrue);
    });

    test('AgentEvent creates structured event with defaults', () {
      final e = AgentEvent(
        id: 'e1',
        runId: 'r1',
        stage: AgentStage.code_generation_started,
        message: 'Начата генерация кода',
        progress: 0.2,
        stepIndex: 1,
        totalSteps: 6,
        meta: {'hint': 'java'},
      );
      expect(e.id, 'e1');
      expect(e.runId, 'r1');
      expect(e.stage, AgentStage.code_generation_started);
      expect(e.severity, AgentSeverity.info); // default
      expect(e.message, contains('генерация'));
      expect(e.progress, closeTo(0.2, 1e-9));
      expect(e.stepIndex, 1);
      expect(e.totalSteps, 6);
      expect(e.meta, containsPair('hint', 'java'));
      expect(e.timestamp, isA<DateTime>());
    });

    test('AgentEvent.legacy builds compatibility wrapper', () {
      final e = AgentEvent.legacy('tool_call', {'x': 1});
      expect(e.stage, AgentStage.pipeline_error);
      expect(e.severity, AgentSeverity.warning);
      expect(e.meta, contains('data'));
    });
  });
}
