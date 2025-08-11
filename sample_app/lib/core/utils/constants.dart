class AppConstants {
  static const String appName = 'AI Chat App';
  static const String defaultSystemPrompt = 'You are a helpful assistant.';
  static const String defaultJsonSchema = '{"key": "value"}';
  
  // API Constants
  static const String baseUrl = 'https://api.deepseek.com';
  static const String chatEndpoint = '/chat/completions';
  
  // Storage Keys
  static const String settingsKey = 'app_settings';
  static const String themeModeKey = 'theme_mode';
  static const String apiKeyKey = 'api_key';
  
  // Default Values
  static const int defaultConnectTimeout = 30000; // 30 seconds
  static const int defaultReceiveTimeout = 30000; // 30 seconds
}
