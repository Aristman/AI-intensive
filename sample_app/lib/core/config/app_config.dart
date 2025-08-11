import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static final AppConfig _instance = AppConfig._internal();
  
  factory AppConfig() => _instance;
  
  AppConfig._internal();
  
  // API Keys
  String get deepSeekApiKey => dotenv.get('DEEPSEEK_API_KEY', fallback: '');
  String? get yandexApiKey => dotenv.get('YANDEX_API_KEY', fallback: null);
  String? get yandexFolderId => dotenv.get('YANDEX_FOLDER_ID', fallback: null);
  
  // API URLs
  String get deepSeekBaseUrl => dotenv.get('DEEPSEEK_BASE_URL', fallback: 'https://api.deepseek.com');
  String get yandexGptBaseUrl => dotenv.get('YANDEX_GPT_BASE_URL', fallback: 'https://llm.api.cloud.yandex.net');
  
  // App settings
  String get defaultModel => dotenv.get('DEFAULT_MODEL', fallback: 'deepseek-chat');
  String get defaultSystemPrompt => dotenv.get('DEFAULT_SYSTEM_PROMPT', fallback: 'You are a helpful AI assistant.');
  
  // Initialize the configuration
  Future<void> init() async {
    await dotenv.load(fileName: 'assets/.env');
  }
}
