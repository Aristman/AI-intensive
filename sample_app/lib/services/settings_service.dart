import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sample_app/models/app_settings.dart';

class SettingsService {
  static const String _settingsKey = 'app_settings';
  
  // Default settings
  static const AppSettings _defaultSettings = AppSettings();
  
  // Get settings from SharedPreferences
  Future<AppSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString(_settingsKey);
    
    if (settingsJson == null) {
      return _defaultSettings;
    }
    
    try {
      final jsonMap = jsonDecode(settingsJson) as Map<String, dynamic>;
      return AppSettings.fromJson(jsonMap);
    } catch (e) {
      debugPrint('Error loading settings: $e');
      return _defaultSettings;
    }
  }
  
  // Save settings to SharedPreferences
  Future<bool> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = jsonEncode(settings.toJson());
      return await prefs.setString(_settingsKey, settingsJson);
    } catch (e) {
      debugPrint('Error saving settings: $e');
      return false;
    }
  }
}
