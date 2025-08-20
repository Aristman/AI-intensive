import 'package:test/test.dart';
import 'package:sample_app/agents/code_ops_agent.dart';
import 'package:sample_app/models/app_settings.dart';

void main() {
  group('CodeOpsAgent MCP guard', () {
    test('execJavaInDocker throws when MCP is disabled or URL missing', () async {
      final agent = CodeOpsAgent(baseSettings: const AppSettings(
        useMcpServer: false,
        mcpServerUrl: null,
      ));

      await expectLater(
        agent.execJavaInDocker(code: 'public class A { public static void main(String[] a){} }'),
        throwsA(isA<StateError>()),
      );
    });

    test('execJavaFilesInDocker throws when MCP is disabled or URL missing', () async {
      final agent = CodeOpsAgent(baseSettings: const AppSettings(
        useMcpServer: false,
        mcpServerUrl: null,
      ));

      final files = [
        {'path': 'A.java', 'content': 'public class A { public static void main(String[] a){} }'},
      ];

      await expectLater(
        agent.execJavaFilesInDocker(files: files),
        throwsA(isA<StateError>()),
      );
    });
  });
}
