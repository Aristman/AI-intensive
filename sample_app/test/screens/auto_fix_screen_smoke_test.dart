import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/screens/auto_fix_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    // Ensure SharedPreferences is available in tests
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AutoFixScreen smoke: run analysis and receive events', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AutoFixScreen())));
    // Wait initial async load in screen (settings, agent init) without pumpAndSettle
    // Poll for the path field to appear with a bounded number of pumps
    Finder pathField = find.byKey(const Key('autofix_path_field'));
    for (int i = 0; i < 40 && tester.any(pathField) == false; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Input path
    pathField = find.byKey(const Key('autofix_path_field'));
    expect(pathField, findsOneWidget);
    await tester.enterText(pathField, 'sample_app/lib/main.dart');

    // Run
    final runBtn = find.byKey(const Key('autofix_analyze_btn'));
    expect(runBtn, findsOneWidget);
    await tester.tap(runBtn);

    // Let async pipeline emit events: poll until we see at least one ListTile or timeout
    Finder tiles = find.byType(ListTile);
    for (int i = 0; i < 60 && tester.any(tiles) == false; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final eventsList = find.byKey(const Key('autofix_events_list'));
    expect(eventsList, findsOneWidget);

    // We expect at least one tile to appear after pipeline completes
    tiles = find.byType(ListTile);
    expect(tiles, findsWidgets);

    // Allow any pending timers inside the agent to complete before test teardown
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
