import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sample_app/models/user_profile.dart';
import 'package:sample_app/services/user_profile_controller.dart';

void main() {
  group('UserProfileController', () {
    late UserProfileController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      controller = UserProfileController();
      await controller.load();
    });

    test('updateName and updateRole persist', () async {
      await controller.updateName('Alice');
      await controller.updateRole('admin');
      expect(controller.profile.name, 'Alice');
      expect(controller.profile.role, 'admin');

      // Reload new controller to verify persistence
      final c2 = UserProfileController();
      await c2.load();
      expect(c2.profile.name, 'Alice');
      expect(c2.profile.role, 'admin');
    });

    test('add/edit/remove preference', () async {
      await controller.addPreference(const ProfileEntry(title: 'p1', description: 'd1'));
      expect(controller.profile.preferences.length, 1);
      expect(controller.profile.preferences.first.title, 'p1');

      await controller.editPreference(0, const ProfileEntry(title: 'p1x', description: 'd2'));
      expect(controller.profile.preferences.first.title, 'p1x');

      await controller.removePreference(0);
      expect(controller.profile.preferences, isEmpty);
    });

    test('add/edit/remove exclusion', () async {
      await controller.addExclusion(const ProfileEntry(title: 'e1', description: 'x'));
      expect(controller.profile.exclusions.length, 1);

      await controller.editExclusion(0, const ProfileEntry(title: 'e2', description: 'y'));
      expect(controller.profile.exclusions.first.title, 'e2');

      await controller.removeExclusion(0);
      expect(controller.profile.exclusions, isEmpty);
    });
  });
}
