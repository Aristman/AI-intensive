import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/screens/profile_screen.dart';
import 'package:sample_app/services/user_profile_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ProfileScreen widget', () {
    late UserProfileController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      controller = UserProfileController();
      await controller.load();
    });

    testWidgets('renders fields and saves basics', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ProfileScreen(controller: controller)));
      await tester.pumpAndSettle();

      // Имя и Роль присутствуют
      expect(find.widgetWithText(TextField, 'Имя'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Роль'), findsOneWidget);

      // Меняем имя и роль
      await tester.enterText(find.widgetWithText(TextField, 'Имя'), 'Alice');
      await tester.enterText(find.widgetWithText(TextField, 'Роль'), 'admin');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Сохранить профиль'));
      await tester.pump();
      // SnackBar
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Профиль сохранён'), findsOneWidget);

      expect(controller.profile.name, 'Alice');
      expect(controller.profile.role, 'admin');
    });

    testWidgets('adds/edits/removes preference via dialogs', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ProfileScreen(controller: controller)));
      await tester.pumpAndSettle();

      // Добавление
      await tester.tap(find.widgetWithText(ElevatedButton, 'Добавить запись').first);
      await tester.pumpAndSettle();
      // Диалог
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Название'), 'p1');
      await tester.enterText(find.widgetWithText(TextField, 'Описание'), 'desc');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Сохранить'));
      await tester.pumpAndSettle();

      expect(controller.profile.preferences.length, 1);
      expect(find.text('p1'), findsOneWidget);

      // Редактирование
      await tester.tap(find.byIcon(Icons.edit).first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      // Поля предзаполнены
      expect(find.widgetWithText(TextField, 'Название'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Название'), 'p1x');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('p1x'), findsOneWidget);

      // Удаление
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(controller.profile.preferences, isEmpty);
    });
  });
}
