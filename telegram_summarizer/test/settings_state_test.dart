import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_summarizer/state/settings_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SettingsState persists and reloads values', () async {
    SharedPreferences.setMockInitialValues({});

    final s1 = SettingsState();
    await s1.load();

    await s1.setLlmModel('yandexgpt');
    await s1.setMcpUrl('ws://example');
    await s1.setMcpClientType('github_telegram');
    await s1.setIamToken('iam');
    await s1.setFolderId('folder');
    await s1.setApiKey('api');

    final s2 = SettingsState();
    await s2.load();

    expect(s2.llmModel, 'yandexgpt');
    expect(s2.mcpUrl, 'ws://example');
    expect(s2.mcpClientType, 'github_telegram');
    expect(s2.iamToken, 'iam');
    expect(s2.folderId, 'folder');
    expect(s2.apiKey, 'api');
  });
}
