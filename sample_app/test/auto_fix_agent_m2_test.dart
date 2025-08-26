import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/agents/auto_fix/auto_fix_agent.dart';
import 'package:sample_app/models/app_settings.dart';

void main() {
  test('AutoFixAgent M2: generates patch for file with trailing spaces and no final newline', () async {
    // Prepare temp file
    final dir = await Directory.systemTemp.createTemp('autofix_m2_');
    final file = File('${dir.path}/test.dart');
    // Line with trailing spaces and missing EOF newline
    await file.writeAsString('void main() {  }  \nprint(42);');

    final agent = AutoFixAgent(initialSettings: const AppSettings());

    final events = <AgentEvent>[];
    final stream = agent.start(AgentRequest('analyze', context: {
      'path': file.path,
      'mode': 'file',
    }));

    final completer = Completer<void>();
    late StreamSubscription sub;
    sub = stream.listen((e) {
      events.add(e);
      if (e.stage == AgentStage.pipeline_complete || e.stage == AgentStage.pipeline_error) {
        completer.complete();
      }
    });

    // Wait end
    await completer.future.timeout(const Duration(seconds: 5));
    await sub.cancel();

    // Find final event
    final done = events.lastWhere((e) => e.stage == AgentStage.pipeline_complete, orElse: () => events.last);
    expect(done.stage, AgentStage.pipeline_complete);
    final meta = done.meta ?? {};
    final patches = (meta['patches'] is List) ? List<Map<String, dynamic>>.from(meta['patches'] as List) : <Map<String, dynamic>>[];

    // At least one patch and it should contain unified diff headers
    expect(patches.isNotEmpty, true);
    final diff = patches.first['diff'] as String? ?? '';
    expect(diff.contains('--- a/'), true);
    expect(diff.contains('+++ b/'), true);

    await dir.delete(recursive: true);
  });
}
