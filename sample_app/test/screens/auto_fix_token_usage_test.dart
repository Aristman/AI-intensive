import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/screens/auto_fix_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTokenAgent implements IAgent {
  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        stateful: false,
        streaming: true,
        reasoning: false,
        tools: {},
        systemPrompt: 'fake',
        responseRules: [],
      );

  @override
  Future<AgentResponse> ask(AgentRequest req) async => AgentResponse(
        text: 'ok',
        isFinal: true,
        mcpUsed: false,
        uncertainty: 0,
      );

  @override
  void dispose() {}

  @override
  void updateSettings(AppSettings settings) {}

  @override
  Stream<AgentEvent>? start(AgentRequest req) {
    final ctrl = StreamController<AgentEvent>();
    final runId = 'fake';
    Future<void>.delayed(const Duration(milliseconds: 10), () {
      ctrl.add(AgentEvent(
        id: 's0',
        runId: runId,
        stage: AgentStage.pipeline_start,
        message: 'start',
      ));
      ctrl.add(AgentEvent(
        id: 'a1',
        runId: runId,
        stage: AgentStage.analysis_started,
        message: 'analysis',
      ));
      // Emit tokens
      ctrl.add(AgentEvent(
        id: 't1',
        runId: runId,
        stage: AgentStage.analysis_result,
        message: 'tokens',
        meta: {
          'tokens': {
            'inputTokens': 123,
            'completionTokens': 45,
            'totalTokens': 168,
          }
        },
      ));
      ctrl.add(AgentEvent(
        id: 'done',
        runId: runId,
        stage: AgentStage.pipeline_complete,
        message: 'done',
        meta: {
          'patches': <Map<String, dynamic>>[],
          'summary': 'ok',
          'tokens': {
            'inputTokens': 0,
            'completionTokens': 2,
            'totalTokens': 2,
          }
        },
      ));
      ctrl.close();
    });
    return ctrl.stream;
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    // Make the test viewport tall enough to avoid Column overflow
    binding.window.physicalSizeTestValue = const Size(1024, 2000);
    binding.window.devicePixelRatioTestValue = 1.0;
  });

  tearDownAll(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.clearPhysicalSizeTestValue();
    binding.window.clearDevicePixelRatioTestValue();
  });

  testWidgets('AutoFixScreen shows token summary and log when tokens arrive', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AutoFixScreen(agent: _FakeTokenAgent()),
      ),
    ));

    // Wait for initial load (settings)
    for (int i = 0; i < 40 && tester.any(find.byKey(const Key('autofix_path_field'))) == false; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Start analysis
    await tester.tap(find.byKey(const Key('autofix_analyze_btn')));

    // Let events flow
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Summary card appears
    expect(find.text('Расход токенов'), findsOneWidget);
    expect(find.text('Вход'), findsOneWidget);
    expect(find.text('Выход'), findsOneWidget);
    expect(find.text('Всего'), findsOneWidget);

    // Expand token log tile and check list
    final tileTitle = find.text('Лог использования токенов');
    expect(tileTitle, findsOneWidget);
    await tester.tap(tileTitle);
    await tester.pumpAndSettle();

    final logList = find.byKey(const Key('autofix_token_log_list'));
    expect(logList, findsOneWidget);
  });
}
