import 'package:flutter/foundation.dart';

class SettingsState extends ChangeNotifier {
  String _llmModel = 'yandexgpt-lite';
  String _mcpUrl = 'ws://localhost:8080';

  String get llmModel => _llmModel;
  String get mcpUrl => _mcpUrl;

  void setLlmModel(String value) {
    if (value == _llmModel) return;
    _llmModel = value;
    notifyListeners();
  }

  void setMcpUrl(String value) {
    if (value == _mcpUrl) return;
    _mcpUrl = value;
    notifyListeners();
  }
}
