import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/utils/unified_diff_utils.dart';

void main() {
  group('parseUnifiedDiffByFile', () {
    test('parses single file diff', () {
      const raw = '''--- a/src/foo.dart
+++ b/src/foo.dart
@@ -1,2 +1,2 @@
-old
+new
-old2
+new2
''';
      final patches = parseUnifiedDiffByFile(raw);
      expect(patches.length, 1);
      expect(patches.first.path, 'src/foo.dart');
      expect(patches.first.diff, raw.trimRight());
    });

    test('parses multiple files diff', () {
      const raw = '''--- a/a.md
+++ b/a.md
@@ -1,1 +1,1 @@
-old
+new
--- a/b.java
+++ b/b.java
@@ -1,1 +1,1 @@
-old
+new
''';
      final patches = parseUnifiedDiffByFile(raw);
      expect(patches.length, 2);
      expect(patches[0].path, 'a.md');
      expect(patches[1].path, 'b.java');
    });

    test('skips malformed headers', () {
      const raw = '''--- a/a.kt
+++ x_wrong
@@ -1,1 +1,1 @@
-old
+new
''';
      final patches = parseUnifiedDiffByFile(raw);
      expect(patches, isEmpty);
    });
  });
}
