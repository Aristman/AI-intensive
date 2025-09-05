import 'package:shared_preferences/shared_preferences.dart';
import 'package:sample_app/models/user_profile.dart';

class UserProfileRepository {
  static const _kProfileKey = 'user_profile_json';

  Future<UserProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kProfileKey);
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

  Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfileKey, profile.toJsonString());
  }
}
