import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/agents/auto_fix/diff_apply_agent.dart';
import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/models/app_settings.dart';

class _FakeLlm implements LlmUseCase {
  final String response;
  _FakeLlm(this.response);
  @override
  Future<String> complete({required List<Map<String, String>> messages, required AppSettings settings}) async {
    return response;
  }
}

void main() {
  group('DiffApplyAgent', () {
    test('extracts code fence content and returns final file', () async {
      final original = 'a\nb\nc\n';
      final diff = '''--- a/file
+++ b/file
@@ -1,3 +1,3 @@
-a
+b
 c
''';
      final llmResp = 'Вот результат:\n```\nx\ny\n```';
      final agent = DiffApplyAgent(useCase: _FakeLlm(llmResp));
      final out = await agent.apply(original: original, diff: diff, settings: const AppSettings());
      expect(out, 'x\ny');
    });

    test('falls back to plain trimmed text if no code fence', () async {
      final agent = DiffApplyAgent(useCase: _FakeLlm('new content\nwith lines'));
      final out = await agent.apply(original: '', diff: '', settings: const AppSettings());
      expect(out, 'new content\nwith lines');
    });
  });
}
