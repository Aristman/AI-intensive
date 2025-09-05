import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Простой синглтон-сервис аутентификации для хранения мок-токена.
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  String? _token;
  String? _login;
  bool _loaded = false;

  static const _kTokenKey = 'auth_token';
  static const _kLoginKey = 'auth_login';

  String? get token => _token;
  String? get login => _login;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kTokenKey);
    _login = prefs.getString(_kLoginKey);
    _loaded = true;
    notifyListeners();
  }

  void setToken(String? token) {
    _token = token?.isNotEmpty == true ? token : null;
    _persist();
    notifyListeners();
  }

  void setLogin(String? login) {
    _login = login?.isNotEmpty == true ? login : null;
    _persist();
    notifyListeners();
  }

  void setCredentials({String? token, String? login}) {
    _token = token?.isNotEmpty == true ? token : null;
    _login = login?.isNotEmpty == true ? login : null;
    _persist();
    notifyListeners();
  }

  void clear() {
    _token = null;
    _login = null;
    _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token == null) {
      await prefs.remove(_kTokenKey);
    } else {
      await prefs.setString(_kTokenKey, _token!);
    }
    if (_login == null) {
      await prefs.remove(_kLoginKey);
    } else {
      await prefs.setString(_kLoginKey, _login!);
    }
  }
}
