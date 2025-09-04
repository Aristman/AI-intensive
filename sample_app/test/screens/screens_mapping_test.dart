import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/screens/screens.dart';

void main() {
  group('Screen factories mapping', () {
    testWidgets('contains factory for each Screen and builds widget with expected key', (tester) async {
      for (final s in Screen.values) {
        expect(screenFactories.containsKey(s), isTrue, reason: 'Factory missing for $s');
        final w = screenFactories[s]!(42);
        expect(w, isA<Widget>());

        // Determine expected key suffix per screen
        final expectedKey = switch (s) {
          Screen.chat => const ValueKey('chat-42'),
          Screen.thinking => const ValueKey('reasoning-42'),
          Screen.multiAgent => const ValueKey('multi-42'),
          Screen.codeOps => const ValueKey('codeops-42'),
          Screen.autoFix => const ValueKey('autofix-42'),
          Screen.github => const ValueKey('github-42'),
          Screen.multiStep =>  const ValueKey('multiStep-42'),
        };

        await tester.pumpWidget(MaterialApp(home: w));
        expect(find.byKey(expectedKey), findsOneWidget, reason: 'Widget for $s should have key ${expectedKey.value}');
      }
    });
  });
}
