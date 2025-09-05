import 'package:flutter/foundation.dart';
import 'package:sample_app/models/user_profile.dart';
import 'package:sample_app/services/user_profile_repository.dart';

class UserProfileController extends ChangeNotifier {
  final UserProfileRepository _repo;
  UserProfile? _profile;
  bool _loading = false;

  UserProfileController({UserProfileRepository? repository}) : _repo = repository ?? UserProfileRepository();

  bool get isLoading => _loading;
  UserProfile get profile => _profile ?? const UserProfile(name: 'Гость', role: 'guest');

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      _profile = await _repo.loadProfile();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> updateName(String name) async {
    final p = profile.copyWith(name: name);
    _profile = p;
    notifyListeners();
    await _repo.saveProfile(p);
  }

  Future<void> updateRole(String role) async {
    final p = profile.copyWith(role: role);
    _profile = p;
    notifyListeners();
    await _repo.saveProfile(p);
  }

  Future<void> addPreference(ProfileEntry entry) async {
    final list = List<ProfileEntry>.from(profile.preferences)..add(entry);
    final p = profile.copyWith(preferences: list);
    _profile = p;
    notifyListeners();
    await _repo.saveProfile(p);
  }

  Future<void> editPreference(int index, ProfileEntry entry) async {
    final list = List<ProfileEntry>.from(profile.preferences);
    if (index < 0 || index >= list.length) return;
    list[index] = entry;
    final p = profile.copyWith(preferences: list);
    _profile = p;
    notifyListeners();
    await _repo.saveProfile(p);
  }

  Future<void> removePreference(int index) async {
    final list = List<ProfileEntry>.from(profile.preferences);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    final p = profile.copyWith(preferences: list);
    _profile = p;
    notifyListeners();
    await _repo.saveProfile(p);
  }

  Future<void> addExclusion(ProfileEntry entry) async {
    final list = List<ProfileEntry>.from(profile.exclusions)..add(entry);
    final p = profile.copyWith(exclusions: list);
    _profile = p;
    notifyListeners();
    await _repo.saveProfile(p);
  }

  Future<void> editExclusion(int index, ProfileEntry entry) async {
    final list = List<ProfileEntry>.from(profile.exclusions);
    if (index < 0 || index >= list.length) return;
    list[index] = entry;
    final p = profile.copyWith(exclusions: list);
    _profile = p;
    notifyListeners();
    await _repo.saveProfile(p);
  }

  Future<void> removeExclusion(int index) async {
    final list = List<ProfileEntry>.from(profile.exclusions);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    final p = profile.copyWith(exclusions: list);
    _profile = p;
    notifyListeners();
    await _repo.saveProfile(p);
  }
}
