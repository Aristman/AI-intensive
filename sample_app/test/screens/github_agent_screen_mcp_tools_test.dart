import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/screens/github_agent_screen.dart';
import 'package:sample_app/services/mcp_client.dart';
import 'package:sample_app/agents/reasoning_agent.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAgent extends ReasoningAgent {
  final String answer;
  FakeAgent(AppSettings settings, this.answer)
      : super(baseSettings: settings, extraSystemPrompt: '')
  {
    // ничего
  }

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
      // Эмулируем JSON-RPC ошибку -32601
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

  group('GitHubAgentScreen MCP tools bridge', () {
    testWidgets('executes get_repo via MCP and shows summary', (tester) async {
      // Arrange
      const settings = AppSettings(
        useMcpServer: true,
        mcpServerUrl: 'ws://fake',
        enabledMCPProviders: {MCPProvider.github},
      );

      final fakeClient = FakeMcpClient(
        tools: {'get_repo', 'list_pull_requests'},
        handlers: {
          'get_repo': (args) => {
                'full_name': '${args['owner']}/${args['repo']}',
                'description': 'Test repository',
              },
        },
      );

      final widget = MaterialApp(
        home: Scaffold(
          body: GitHubAgentScreen(
            initialSettings: settings,
            agentFactory: (s, _) => FakeAgent(s, '{"tool":"get_repo","args":{"owner":"aristman","repo":"AI-intensive"}}'),
            mcpClientFactory: () => fakeClient,
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      // Act: нажмём отправку
      await tester.enterText(find.byKey(const Key('github_query_field')), 'repo info');
      await tester.tap(find.byKey(const Key('github_send_btn')));
      await tester.pumpAndSettle();

      // Assert: отображён результат краткого саммари
      expect(find.textContaining('Репозиторий: aristman/AI-intensive'), findsOneWidget);
    });

    testWidgets('shows friendly error and tools list when tool is not available', (tester) async {
      // Arrange: list_pull_requests отсутствует в tools/list
      const settings = AppSettings(
        useMcpServer: true,
        mcpServerUrl: 'ws://fake',
        enabledMCPProviders: {MCPProvider.github},
      );

      final fakeClient = FakeMcpClient(
        tools: {'get_repo'},
        handlers: {
          'get_repo': (args) => {
                'full_name': '${args['owner']}/${args['repo']}',
                'description': 'Test repository',
              },
        },
      );

      final widget = MaterialApp(
        home: Scaffold(
          body: GitHubAgentScreen(
            initialSettings: settings,
            agentFactory: (s, _) => FakeAgent(s, '{"tool":"list_pull_requests","args":{"owner":"aristman","repo":"AI-intensive"}}'),
            mcpClientFactory: () => fakeClient,
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      // Act
      await tester.enterText(find.byKey(const Key('github_query_field')), 'list prs');
      await tester.tap(find.byKey(const Key('github_send_btn')));
      await tester.pumpAndSettle();

      // Assert: дружелюбная ошибка и перечень доступных инструментов
      expect(find.textContaining('Инструмент "list_pull_requests" недоступен'), findsOneWidget);
      expect(find.textContaining('Доступные инструменты: get_repo'), findsOneWidget);
    });

    testWidgets('clear history button clears UI and persistent storage', (tester) async {
      // Arrange: подготовим историю в SharedPreferences
      SharedPreferences.setMockInitialValues({});
      const key = 'conv_history::github:aristman/AI-intensive';
      final stored = jsonEncode([
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hello'},
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, stored);

      const settings = AppSettings(
        useMcpServer: true,
        mcpServerUrl: 'ws://fake',
        enabledMCPProviders: {MCPProvider.github},
      );

      final fakeClient = FakeMcpClient(tools: {'get_repo'}, handlers: {});

      final widget = MaterialApp(
        home: Scaffold(
          body: GitHubAgentScreen(
            initialSettings: settings,
            agentFactory: (s, _) => FakeAgent(s, 'no-op'),
            mcpClientFactory: () => fakeClient,
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      // История загрузилась в UI
      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('hi'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);

      // Act: нажмём очистку
      await tester.tap(find.byKey(const Key('github_clear_history_btn')));
      await tester.pumpAndSettle();

      // Assert: UI очищен
      expect(find.text('hi'), findsNothing);
      expect(find.text('hello'), findsNothing);

      // И персистентное хранилище очищено
      expect(prefs.getString(key), isNull);
    });

    testWidgets('handles MCP -32601 gracefully when server returns Tool not found on call', (tester) async {
      // Arrange: инструмент заявлен в tools/list, но tools/call вернёт -32601
      const settings = AppSettings(
        useMcpServer: true,
        mcpServerUrl: 'ws://fake',
        enabledMCPProviders: {MCPProvider.github},
      );

      final fakeClient = FakeMcpClient(
        tools: {'list_pull_requests'},
        handlers: {
          // Пусто: вызов list_pull_requests приведёт к Future.error с code -32601
        },
      );

      final widget = MaterialApp(
        home: Scaffold(
          body: GitHubAgentScreen(
            initialSettings: settings,
            agentFactory: (s, _) => FakeAgent(s, '{"tool":"list_pull_requests","args":{"owner":"aristman","repo":"AI-intensive"}}'),
            mcpClientFactory: () => fakeClient,
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      // Act
      await tester.enterText(find.byKey(const Key('github_query_field')), 'list prs');
      await tester.tap(find.byKey(const Key('github_send_btn')));
      await tester.pumpAndSettle();

      // Assert: сообщение про MCP -32601 и список доступных инструментов
      expect(find.textContaining('MCP -32601'), findsOneWidget);
      expect(find.textContaining('Доступные инструменты: list_pull_requests'), findsOneWidget);
    });
  });
}
