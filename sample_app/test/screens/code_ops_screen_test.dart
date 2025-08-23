import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/screens/code_ops_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CodeOpsScreen MCP status chip', () {
    setUp(() async {
      // reset prefs before each test
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('shows MCP off when useMcpServer=false or URL empty', (tester) async {
      final settings = const AppSettings(
        useMcpServer: false,
        mcpServerUrl: '',
      );
      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode(settings.toJson()),
      });

      await tester.pumpWidget(const MaterialApp(home: CodeOpsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('MCP off'), findsOneWidget);
    });

    testWidgets('shows MCP ready when useMcpServer=true and URL set', (tester) async {
      final settings = const AppSettings(
        useMcpServer: true,
        mcpServerUrl: 'ws://localhost:3001',
      );
      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode(settings.toJson()),
      });

      await tester.pumpWidget(const MaterialApp(home: CodeOpsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('MCP ready'), findsOneWidget);
    });
  });
}
