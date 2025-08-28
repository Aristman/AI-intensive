import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SettingsState extends ChangeNotifier {
  static const _kLlmModel = 'llmModel';
  static const _kMcpUrl = 'mcpUrl';
  static const _kIamToken = 'iamToken';
  static const _kFolderId = 'folderId';
  static const _kApiKey = 'apiKey';

  String _llmModel = 'yandexgpt-lite';
  String _mcpUrl = 'ws://localhost:8080';
  String _iamToken = '';
  String _folderId = '';
  String _apiKey = '';

  String get llmModel => _llmModel;
  String get mcpUrl => _mcpUrl;
  String get iamToken => _iamToken;
  String get folderId => _folderId;
  String get apiKey => _apiKey;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Defaults from .env if present
    String? getEnv(String key) {
      try {
        return dotenv.maybeGet(key);
      } catch (_) {
        return null;
      }
    }
    final envModel = getEnv('YANDEX_MODEL_URI') ?? getEnv('LLM_MODEL');
    final envMcp = getEnv('MCP_URL');
    final envIam = getEnv('IAM_TOKEN') ?? getEnv('YANDEX_IAM_TOKEN') ?? getEnv('YC_IAM_TOKEN');
    final envFolder = getEnv('X_FOLDER_ID') ?? getEnv('YANDEX_FOLDER_ID');
    final envApi = getEnv('YANDEX_API_KEY');

    _llmModel = prefs.getString(_kLlmModel) ?? envModel ?? _llmModel;
    _mcpUrl = prefs.getString(_kMcpUrl) ?? envMcp ?? _mcpUrl;
    _iamToken = prefs.getString(_kIamToken) ?? envIam ?? '';
    _folderId = prefs.getString(_kFolderId) ?? envFolder ?? '';
    _apiKey = prefs.getString(_kApiKey) ?? envApi ?? '';
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLlmModel, _llmModel);
    await prefs.setString(_kMcpUrl, _mcpUrl);
    await prefs.setString(_kIamToken, _iamToken);
    await prefs.setString(_kFolderId, _folderId);
    await prefs.setString(_kApiKey, _apiKey);
  }

  Future<void> setLlmModel(String value) async {
    if (value == _llmModel) return;
    _llmModel = value;
    await _save();
    notifyListeners();
  }

  Future<void> setMcpUrl(String value) async {
    if (value == _mcpUrl) return;
    _mcpUrl = value;
    await _save();
    notifyListeners();
  }

  Future<void> setIamToken(String value) async {
    if (value == _iamToken) return;
    _iamToken = value;
    await _save();
    notifyListeners();
  }

  Future<void> setFolderId(String value) async {
    if (value == _folderId) return;
    _folderId = value;
    await _save();
    notifyListeners();
  }

  Future<void> setApiKey(String value) async {
    if (value == _apiKey) return;
    _apiKey = value;
    await _save();
    notifyListeners();
  }
}
