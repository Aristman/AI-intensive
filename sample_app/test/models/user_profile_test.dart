import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/models/user_profile.dart';

void main() {
  group('UserProfile model', () {
    test('toJson/fromJson roundtrip', () {
      final src = UserProfile(
        name: 'Alice',
        role: 'admin',
        preferences: const [ProfileEntry(title: 'dark_mode', description: 'Use dark theme')],
        exclusions: const [ProfileEntry(title: 'no_ads', description: 'Disable ads')],
      );
      final json = src.toJson();
      final restored = UserProfile.fromJson(json);
      expect(restored.name, 'Alice');
      expect(restored.role, 'admin');
      expect(restored.preferences.length, 1);
      expect(restored.preferences.first.title, 'dark_mode');
      expect(restored.exclusions.length, 1);
      expect(restored.exclusions.first.description, 'Disable ads');
    });

    test('toJsonString/fromJsonString roundtrip', () {
      final src = const UserProfile(name: 'Bob', role: 'user');
      final s = src.toJsonString();
      final restored = UserProfile.fromJsonString(s);
      expect(restored.name, 'Bob');
      expect(restored.role, 'user');
    });

    test('copyWith updates fields', () {
      final src = const UserProfile(name: 'A', role: 'guest');
      final updated = src.copyWith(name: 'B', role: 'user');
      expect(updated.name, 'B');
      expect(updated.role, 'user');
    });

    test('ProfileEntry copyWith', () {
      const e = ProfileEntry(title: 't', description: 'd');
      final u = e.copyWith(description: 'x');
      expect(u.title, 't');
      expect(u.description, 'x');
    });
  });
}
