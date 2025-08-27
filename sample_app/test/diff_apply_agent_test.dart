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

  @override
  Future<LlmResponse> completeWithUsage({required List<Map<String, String>> messages, required AppSettings settings}) async {
    return LlmResponse(text: response, usage: {'inputTokens': 10, 'completionTokens': 5, 'totalTokens': 15});
  }
}

void main() {
  group('DiffApplyAgent', () {
    test('applies full-file unified diff locally without using tokens', () async {
      final original = 'line1\nline2\n';
      final newContent = 'alpha\nbeta\n';
      final diff = '''--- a/file
+++ b/file
@@ -1,2 +1,2 @@
-line1
-line2
+alpha
+beta
''';
      final agent = DiffApplyAgent();
      final result = await agent.apply(original: original, diff: diff, settings: const AppSettings());
      expect(result.content, newContent);
      expect(result.tokens, isNull, reason: 'Local application should not consume tokens');
    });

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
      final result = await agent.apply(original: original, diff: diff, settings: const AppSettings());
      expect(result.content, 'x\ny');
      expect(result.tokens, isNotNull);
      expect(result.tokens!['inputTokens'], 10);
      expect(result.tokens!['completionTokens'], 5);
      expect(result.tokens!['totalTokens'], 15);
    });

    test('falls back to plain trimmed text if no code fence', () async {
      final agent = DiffApplyAgent(useCase: _FakeLlm('new content\nwith lines'));
      final result = await agent.apply(original: '', diff: '', settings: const AppSettings());
      expect(result.content, 'new content\nwith lines');
      expect(result.tokens, isNotNull);
    });
  });
}
