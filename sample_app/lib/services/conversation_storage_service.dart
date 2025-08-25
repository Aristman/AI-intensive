import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Хранение истории диалога в SharedPreferences
/// Формат: List<Map<String,String>> с полями {role: 'user'|'assistant', content: '...'}
class ConversationStorageService {
  static String _prefKey(String key) => 'conv_history::$key';

  Future<List<Map<String, String>>> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey(key));
    if (raw == null || raw.isEmpty) return <Map<String, String>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => {
                  'role': m['role']?.toString() ?? 'user',
                  'content': m['content']?.toString() ?? '',
                })
            .where((m) => m['content']!.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return <Map<String, String>>[];
  }

  Future<void> save(String key, List<Map<String, String>> messages) async {
    final prefs = await SharedPreferences.getInstance();
    // Фильтрация на всякий случай
    final normalized = messages
        .map((m) => {
              'role': (m['role'] == 'assistant') ? 'assistant' : 'user',
              'content': (m['content'] ?? '').toString(),
            })
        .where((m) => m['content']!.isNotEmpty)
        .toList();
    await prefs.setString(_prefKey(key), jsonEncode(normalized));
  }

  Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey(key));
  }
}
