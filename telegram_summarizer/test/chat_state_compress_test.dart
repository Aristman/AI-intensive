import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_summarizer/agents/simple_agent.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:telegram_summarizer/state/settings_state.dart';

class _FakeLlm implements LlmUseCase {
  @override
  Future<String> complete({
    required List<Map<String, String>> messages,
    required String modelUri,
    required String iamToken,
    required String apiKey,
    required String folderId,
    double temperature = 0.2,
    int maxTokens = 128,
    client,
    Duration timeout = const Duration(seconds: 20),
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async {
    if (messages.isNotEmpty &&
        messages.last['role'] == 'system' &&
        (messages.last['content'] ?? '').contains('Сожми диалог')) {
      return 'SUM';
    }
    // Echo last user content prefix
    final lastUser = messages.reversed.firstWhere(
      (m) => m['role'] == 'user',
      orElse: () => const {'role': 'user', 'content': ''},
    );
    final content = lastUser['content'] ?? '';
    return 'REPLY:${content.substring(0, content.length > 10 ? 10 : content.length)}';
  }
}

Future<SettingsState> _settings() async {
  final s = SettingsState();
  await s.load();
  await s.setApiKey('api');
  await s.setFolderId('folder');
  return s;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SimpleAgent auto-compresses its internal context when threshold exceeded', () async {
    final settings = await _settings();
    final agent = SimpleAgent(_FakeLlm(), systemPrompt: 'You are helpful');
    await agent.load();

    // Build a long message to exceed ~2000 tokens (4 chars per token => ~8000 chars)
    final longText = 'A' * 8200;

    final reply = await agent.ask(longText, settings);
    expect(reply.startsWith('REPLY:'), true);

    // History should be: [system summary], [user long], [assistant reply]
    expect(agent.history.length, 3);
    expect(agent.history[0]['role'], 'system');
    expect(agent.history[0]['content']?.contains('Сводка диалога'), true);
    expect((agent.history[1]['content'] ?? '').length, 8200);
    expect(agent.history[2]['role'], 'assistant');
  });
}
