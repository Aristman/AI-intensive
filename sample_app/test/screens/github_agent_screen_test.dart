import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/screens/github_agent_screen.dart';

void main() {
  group('GitHubAgentScreen', () {
    testWidgets('is fully blocked when MCP is disabled', (tester) async {
      // Arrange: MCP off
      const settings = AppSettings(
        useMcpServer: false,
        enabledMCPProviders: {},
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GitHubAgentScreen(
              key: ValueKey('github-42'),
              initialSettings: settings,
            ),
          ),
        ),
      );

      // Wait for initial state
      await tester.pumpAndSettle();

      // Assert: banner shown, send disabled
      expect(find.byKey(const Key('github_mcp_block_banner')), findsOneWidget);
      final IconButton sendBtn = tester.widget(find.byKey(const Key('github_send_btn')));
      expect(sendBtn.onPressed, isNull);
    });

    testWidgets('query is enabled when MCP is ready and owner/repo filled', (tester) async {
      // Arrange: MCP ready
      const settings = AppSettings(
        useMcpServer: true,
        mcpServerUrl: 'ws://localhost:3001',
        enabledMCPProviders: {MCPProvider.github},
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GitHubAgentScreen(
              key: ValueKey('github-43'),
              initialSettings: settings,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // No block banner
      expect(find.byKey(const Key('github_mcp_block_banner')), findsNothing);

      // Send button enabled (owner/repo prefilled by default)
      final IconButton sendBtn = tester.widget(find.byKey(const Key('github_send_btn')));
      expect(sendBtn.onPressed, isNotNull);
    });
  });
}
