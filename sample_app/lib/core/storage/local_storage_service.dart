import 'package:shared_preferences/shared_preferences.dart';
import '../error/exceptions.dart';

abstract class LocalStorageService {
  Future<bool> saveString(String key, String value);
  Future<String?> getString(String key);
  Future<bool> remove(String key);
  Future<bool> clear();
}

class LocalStorageServiceImpl implements LocalStorageService {
  final SharedPreferences sharedPreferences;

  LocalStorageServiceImpl({required this.sharedPreferences});

  @override
  Future<bool> saveString(String key, String value) async {
    try {
      return await sharedPreferences.setString(key, value);
    } catch (e) {
      throw CacheException('Failed to save data: $e');
    }
  }

  @override
  Future<String?> getString(String key) async {
    try {
      return sharedPreferences.getString(key);
    } catch (e) {
      throw CacheException('Failed to get data: $e');
    }
  }

  @override
  Future<bool> remove(String key) async {
    try {
      return await sharedPreferences.remove(key);
    } catch (e) {
      throw CacheException('Failed to remove data: $e');
    }
  }

  @override
  Future<bool> clear() async {
    try {
      return await sharedPreferences.clear();
    } catch (e) {
      throw CacheException('Failed to clear storage: $e');
    }
  }
}
