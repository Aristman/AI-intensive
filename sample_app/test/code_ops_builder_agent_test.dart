import 'package:test/test.dart';
import 'package:sample_app/agents/code_ops_builder_agent.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';

void main() {
  group('CodeOpsBuilderAgent basics', () {
    test('capabilities and tools', () {
      final agent = CodeOpsBuilderAgent(baseSettings: const AppSettings());
      final caps = agent.capabilities;
      expect(caps.stateful, isTrue);
      expect(caps.streaming, isFalse);
      expect(caps.reasoning, isTrue);
      expect(caps.tools, containsAll(['docker_exec_java', 'docker_start_java']));

      expect(agent is IToolingAgent, isTrue);
      expect(agent.supportsTool('docker_exec_java'), isTrue);
      expect(agent.supportsTool('docker_start_java'), isTrue);
      expect(agent.supportsTool('unknown_tool'), isFalse);
    });

    test('docker_exec_java guard through callTool when MCP disabled', () async {
      final agent = CodeOpsBuilderAgent(
        baseSettings: const AppSettings(
          useMcpServer: false,
          mcpServerUrl: null,
        ),
      );

      await expectLater(
        agent.callTool('docker_exec_java', {
          'code': 'public class A { public static void main(String[] a){} }',
          'filename': 'A.java',
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('docker_exec_java files guard through callTool when MCP disabled', () async {
      final agent = CodeOpsBuilderAgent(
        baseSettings: const AppSettings(
          useMcpServer: false,
          mcpServerUrl: null,
        ),
      );

      final files = [
        {'path': 'A.java', 'content': 'public class A { public static void main(String[] a){} }'},
      ];

      await expectLater(
        agent.callTool('docker_exec_java', {'files': files}),
        throwsA(isA<StateError>()),
      );
    });

    test('start() returns null (no streaming yet)', () {
      final agent = CodeOpsBuilderAgent(baseSettings: const AppSettings());
      final s = agent.start(AgentRequest('ping'));
      expect(s, isNull);
    });
  });
}
