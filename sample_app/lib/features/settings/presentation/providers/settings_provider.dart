import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/enums/response_format.dart';

enum NeuralNetwork { deepseek, yandexgpt }

class SettingsProvider with ChangeNotifier {
  static const String _selectedModelKey = 'selected_model';
  static const String _systemPromptKey = 'system_prompt';
  static const String _responseFormatKey = 'response_format';
  static const String _customJsonSchemaKey = 'custom_json_schema';

  late final SharedPreferences _prefs;
  
  String _selectedModel = 'deepseek-chat';
  String _systemPrompt = 'You are a helpful assistant.';
  ResponseFormat _responseFormat = ResponseFormat.text;
  String? _customJsonSchema;

  SettingsProvider(SharedPreferences prefs) : _prefs = prefs {
    _loadSettings();
  }

  // Getters
  String get selectedModel => _selectedModel;
  String get systemPrompt => _systemPrompt;
  ResponseFormat get responseFormat => _responseFormat;
  String? get customJsonSchema => _customJsonSchema;

  // Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    _selectedModel = _prefs.getString(_selectedModelKey) ?? 'deepseek-chat';
    _systemPrompt = _prefs.getString(_systemPromptKey) ?? 'You are a helpful assistant.';
    _responseFormat = ResponseFormat.values.firstWhere(
      (e) => e.toString() == 'ResponseFormat.${_prefs.getString(_responseFormatKey)}',
      orElse: () => ResponseFormat.text,
    );
    _customJsonSchema = _prefs.getString(_customJsonSchemaKey);
    notifyListeners();
  }

  // Save settings to SharedPreferences
  Future<void> _saveSettings() async {
    await _prefs.setString(_selectedModelKey, _selectedModel);
    await _prefs.setString(_systemPromptKey, _systemPrompt);
    await _prefs.setString(_responseFormatKey, _responseFormat.toString().split('.').last);
    if (_customJsonSchema != null) {
      await _prefs.setString(_customJsonSchemaKey, _customJsonSchema!);
    } else {
      await _prefs.remove(_customJsonSchemaKey);
    }
  }

  // Update methods
  Future<void> updateSelectedModel(String value) async {
    _selectedModel = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> updateSystemPrompt(String value) async {
    _systemPrompt = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> updateResponseFormat(ResponseFormat value) async {
    _responseFormat = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> updateCustomJsonSchema(String? value) async {
    _customJsonSchema = value;
    await _saveSettings();
    notifyListeners();
  }
}
