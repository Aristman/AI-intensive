import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sample_app/models/user_profile.dart';
import 'package:sample_app/services/user_profile_repository.dart';

void main() {
  group('UserProfileRepository', () {
    late UserProfileRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = UserProfileRepository();
    });

    test('returns default guest profile when empty', () async {
      final p = await repo.loadProfile();
      expect(p.name, 'Гость');
      expect(p.role, 'guest');
      expect(p.preferences, isEmpty);
      expect(p.exclusions, isEmpty);
    });

    test('save and load roundtrip', () async {
      final src = UserProfile(
        name: 'Tester',
        role: 'user',
        preferences: const [ProfileEntry(title: 'p1', description: 'd1')],
        exclusions: const [ProfileEntry(title: 'e1', description: 'd2')],
      );
      await repo.saveProfile(src);
      final restored = await repo.loadProfile();
      expect(restored.name, 'Tester');
      expect(restored.role, 'user');
      expect(restored.preferences.single.title, 'p1');
      expect(restored.exclusions.single.title, 'e1');
    });
  });
}
