import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/screens/github_agent_screen.dart';
import 'package:sample_app/agents/reasoning_agent.dart';
import 'package:sample_app/services/mcp_client.dart';

class FakeAgent extends ReasoningAgent {
  final String answer;
  FakeAgent(AppSettings settings, this.answer)
      : super(baseSettings: settings, extraSystemPrompt: '');

  @override
  Future<Map<String, dynamic>> ask(String userText) async {
    return {
      'result': ReasoningResult(text: answer, isFinal: true),
      'mcp_used': false,
    };
  }
}

class FakeMcpClient extends McpClient {
  final Set<String> tools;
  final Map<String, dynamic Function(Map<String, dynamic>)> handlers;

  FakeMcpClient({required this.tools, required this.handlers});

  @override
  Future<void> connect(String url) async {}

  @override
  Future<Map<String, dynamic>> initialize({Duration? timeout}) async => {'ok': true};

  @override
  Future<Map<String, dynamic>> toolsList({Duration? timeout}) async {
    return {
      'tools': tools.map((t) => {'name': t}).toList(),
    };
  }

  @override
  Future<dynamic> toolsCall(String name, Map<String, dynamic> args, {Duration? timeout}) async {
    final h = handlers[name];
    if (h == null) {
      return Future.error({'code': -32601, 'message': 'Tool not found', 'data': name});
    }
    final res = h(args);
    return {'result': res};
  }

  @override
  Future<void> close() async {}
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('GitHubAgentScreen local settings dialog', () {
    testWidgets('updates repo context label and persists across rebuild', (tester) async {
      // Arrange: MCP ready, no default owner/repo
      const settings = AppSettings(
        useMcpServer: true,
        mcpServerUrl: 'ws://fake',
        enabledMCPProviders: {MCPProvider.github},
      );

      final fakeClient = FakeMcpClient(tools: {'get_repo'}, handlers: {
        'get_repo': (args) => {
              'full_name': '${args['owner']}/${args['repo']}',
              'html_url': 'https://github.com/${args['owner']}/${args['repo']}',
            },
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GitHubAgentScreen(
            initialSettings: settings,
            agentFactory: (s, _) => FakeAgent(s, '{"tool":"get_repo","args":{}}'),
            mcpClientFactory: () => fakeClient,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Act: open local settings dialog and set new owner/repo
      await tester.tap(find.byKey(const Key('github_local_settings_btn')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('github_local_owner_field')), 'octocat');
      await tester.enterText(find.byKey(const Key('github_local_repo_field')), 'Hello-World');
      await tester.tap(find.byKey(const Key('github_local_save_btn')));
      await tester.pumpAndSettle();

      // Assert: header shows new context
      expect(find.byKey(const Key('github_repo_context_label')), findsOneWidget);
      expect(find.textContaining('octocat/Hello-World'), findsOneWidget);

      // Rebuild without initialSettings to check persistence
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GitHubAgentScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('github_repo_context_label')), findsOneWidget);
      expect(find.textContaining('octocat/Hello-World'), findsOneWidget);
    });

    testWidgets('uses owner/repo from settings when missing in tool args', (tester) async {
      // Arrange
      const settings = AppSettings(
        useMcpServer: true,
        mcpServerUrl: 'ws://fake',
        enabledMCPProviders: {MCPProvider.github},
      );

      String? receivedOwner;
      String? receivedRepo;

      final fakeClient = FakeMcpClient(tools: {'get_repo'}, handlers: {
        'get_repo': (args) {
          receivedOwner = args['owner']?.toString();
          receivedRepo = args['repo']?.toString();
          return {
            'full_name': '${args['owner']}/${args['repo']}',
            'description': 'ok',
          };
        },
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GitHubAgentScreen(
            initialSettings: settings,
            agentFactory: (s, _) => FakeAgent(s, '{"tool":"get_repo","args":{}}'),
            mcpClientFactory: () => fakeClient,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Set owner/repo via dialog
      await tester.tap(find.byKey(const Key('github_local_settings_btn')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('github_local_owner_field')), 'my-org');
      await tester.enterText(find.byKey(const Key('github_local_repo_field')), 'my-repo');
      await tester.tap(find.byKey(const Key('github_local_save_btn')));
      await tester.pumpAndSettle();

      // Trigger tool execution (agent outputs JSON without owner/repo)
      await tester.enterText(find.byKey(const Key('github_query_field')), 'info');
      await tester.tap(find.byKey(const Key('github_send_btn')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(receivedOwner, 'my-org');
      expect(receivedRepo, 'my-repo');
      expect(find.textContaining('Репозиторий: my-org/my-repo'), findsOneWidget);
    });

    testWidgets('list limits from settings affect summaries', (tester) async {
      // Arrange
      const settings = AppSettings(
        useMcpServer: true,
        mcpServerUrl: 'ws://fake',
        enabledMCPProviders: {MCPProvider.github},
      );

      final fakeClient = FakeMcpClient(tools: {'list_pull_requests'}, handlers: {
        'list_pull_requests': (args) => [
              {'number': 1, 'title': 'PR one', 'state': 'open'},
              {'number': 2, 'title': 'PR two', 'state': 'closed'},
            ],
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GitHubAgentScreen(
            initialSettings: settings,
            agentFactory: (s, _) => FakeAgent(s, '{"tool":"list_pull_requests","args":{}}'),
            mcpClientFactory: () => fakeClient,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Set limits via dialog: other=1
      await tester.tap(find.byKey(const Key('github_local_settings_btn')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('github_local_other_limit_field')), '1');
      await tester.tap(find.byKey(const Key('github_local_save_btn')));
      await tester.pumpAndSettle();

      // Trigger tool execution
      await tester.enterText(find.byKey(const Key('github_query_field')), 'list prs');
      await tester.tap(find.byKey(const Key('github_send_btn')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Only 1 line expected due to limit=1
      final prLines = find.textContaining('#');
      expect(prLines, findsOneWidget);
      expect(find.textContaining('#1 PR one (open)'), findsOneWidget);
      expect(find.textContaining('#2 PR two (closed)'), findsNothing);
    });
  });
}
