import 'package:shared_preferences/shared_preferences.dart';
import 'package:sample_app/models/user_profile.dart';

class UserProfileRepository {
  static const _kProfileKeyBase = 'user_profile_json';
  static const _kLegacyGlobalKey = 'user_profile_json'; // прежний общий ключ

  String _keyFor(String? login) {
    final who = (login == null || login.isEmpty) ? 'guest' : login;
    return '$_kProfileKeyBase:$who';
  }

  Future<void> _ensureLegacyCleared(SharedPreferences prefs) async {
    // Удаляем старый общий профиль, чтобы исключить случайное использование
    if (prefs.containsKey(_kLegacyGlobalKey)) {
      await prefs.remove(_kLegacyGlobalKey);
    }
  }

  Future<UserProfile> loadProfile({String? login}) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureLegacyCleared(prefs);
    final json = prefs.getString(_keyFor(login));
    if (json == null || json.isEmpty) {
      // Значения по умолчанию
      return const UserProfile(name: 'Гость', role: 'guest');
    }
    try {
      return UserProfile.fromJsonString(json);
    } catch (_) {
      return const UserProfile(name: 'Гость', role: 'guest');
    }
  }

  Future<void> saveProfile(UserProfile profile, {String? login}) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureLegacyCleared(prefs);
    await prefs.setString(_keyFor(login), profile.toJsonString());
  }
}
