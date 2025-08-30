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
    // Если в конце есть системная инструкция на компрессию — возвращаем SUM.
    if (messages.isNotEmpty &&
        messages.last['role'] == 'system' &&
        (messages.last['content'] ?? '').contains('Сожми диалог')) {
      return 'SUMMARIZED';
    }
    // Иначе просто эхо последнего пользовательского сообщения
    final lastUser = messages.reversed.firstWhere(
      (m) => m['role'] == 'user',
      orElse: () => const {'role': 'user', 'content': ''},
    );
    return 'REPLY: ${lastUser['content'] ?? ''}';
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SettingsState> settings0() async {
    final s = SettingsState();
    await s.load();
    await s.setApiKey('api');
    await s.setFolderId('folder');
    return s;
  }

  test('SimpleAgent.ask adds to history and returns reply', () async {
    final settings = await settings0();
    final agent = SimpleAgent(_FakeLlm(), systemPrompt: 'You are helpful');

    final reply = await agent.ask('Hello', settings);

    expect(reply, 'REPLY: Hello');
    expect(agent.history.length, 3); // system + user + assistant
    expect(agent.history[0]['role'], 'system');
    expect(agent.history[1]['role'], 'user');
    expect(agent.history[2]['role'], 'assistant');
  });

  test('SimpleAgent.compressContext reduces history, no keepLastUser',
      () async {
    final settings = await settings0();
    final agent = SimpleAgent(_FakeLlm(), systemPrompt: 'S');
    await agent.ask('A', settings);
    await agent.ask('B', settings);

    await agent.compressContext(settings, keepLastUser: false);

    expect(agent.history.length, 1);
    expect(agent.history[0]['role'], 'system');
    final content = agent.history[0]['content'] ?? '';
    expect(content, contains('Сводка диалога'));
    expect(content, contains('SUMMARIZED'));
  });

  test('SimpleAgent.compressContext keeps last user when keepLastUser=true',
      () async {
    final settings = await settings0();
    final agent = SimpleAgent(_FakeLlm());
    await agent.ask('first', settings);
    await agent.ask('second', settings);

    await agent.compressContext(settings, keepLastUser: true);

    expect(agent.history.length, 2);
    expect(agent.history[0]['role'], 'system');
    expect(agent.history[1]['role'], 'user');
    expect(agent.history[1]['content'], 'second');
  });
}
