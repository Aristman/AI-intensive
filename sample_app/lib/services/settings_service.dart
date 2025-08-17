import 'dart:convert';
import 'dart:developer';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sample_app/models/app_settings.dart';

class SettingsService {
  static const String _settingsKey = 'app_settings';
  
  // Default settings
  static AppSettings _getDefaultSettings() {
    String token = '';
    try {
      token = dotenv.env['GITHUB_MCP_TOKEN'] ?? '';
    } catch (e) {
      // Dotenv not initialized in tests or runtime: fall back to empty token
      token = '';
    }
    return AppSettings(
      githubMcpToken: token,
    );
  }
  
  // Get settings from SharedPreferences
  Future<AppSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString(_settingsKey);
    
    if (settingsJson == null) {
      return _getDefaultSettings();
    }
    
    try {
      final jsonMap = jsonDecode(settingsJson) as Map<String, dynamic>;
      return AppSettings.fromJson(jsonMap);
    } catch (e) {
      log('Error loading settings: $e');
      return _getDefaultSettings();
    }
  }
  
  // Save settings to SharedPreferences
  Future<bool> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = jsonEncode(settings.toJson());
      return await prefs.setString(_settingsKey, settingsJson);
    } catch (e) {
      log('Error saving settings: $e');
      return false;
    }
  }
}
