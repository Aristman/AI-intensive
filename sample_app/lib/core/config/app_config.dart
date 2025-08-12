import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

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
  
  // List of required environment variables
  static const List<String> _requiredVars = [
    'DEEPSEEK_API_KEY',
  ];

  // Validate that all required environment variables are set
  void _validateEnvVars() {
    final missingVars = _requiredVars.where((varName) {
      final value = dotenv.maybeGet(varName, fallback: null);
      return value == null || value.isEmpty;
    }).toList();

    if (missingVars.isNotEmpty) {
      throw Exception(
        'Missing required environment variables: ${missingVars.join(', ')}. '
        'Please check your .env file and make sure all required variables are set.\n'
        'Required variables: ${_requiredVars.join(', ')}',
      );
    }
  }

  // Initialize the configuration
  Future<void> init() async {
    try {
      await dotenv.load(fileName: '.env');
      _validateEnvVars();
      
      // Log successful initialization
      debugPrint('AppConfig initialized successfully');
      debugPrint('Using DeepSeek API at: $deepSeekBaseUrl');
      debugPrint('Default model: $defaultModel');
    } catch (e, stackTrace) {
      debugPrint('Error initializing AppConfig: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
