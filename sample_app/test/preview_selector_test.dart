import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/utils/preview_selector.dart';

void main() {
  group('preview_selector', () {
    const path = 'lib/a.dart';

    test('includes head and windows around issues, merges overlaps', () {
      final content = List.generate(120, (i) => 'line ${i + 1}').join('\n');
      final issues = [
        {'file': path, 'line': 15},
        {'file': path, 'line': 20}, // overlap with previous window
        {'file': path, 'line': 90},
      ];
      final out = buildSelectivePreview(
        path: path,
        content: content,
        issues: issues,
        headLines: 10,
        context: 5,
        maxChars: 2000,
      );

      // Head present
      expect(out.contains('line 1'), isTrue);
      expect(out.contains('line 10'), isTrue);
      // Overlapped windows are merged - we should see lines around 15..20
      expect(out.contains('line 10'), isTrue); // end of head touches window start
      expect(out.contains('line 15'), isTrue);
      expect(out.contains('line 20'), isTrue);
      // Far window near 90 is present
      expect(out.contains('line 90'), isTrue);
      // Separator between non-overlapping segments
      expect(out.contains('\n...\n'), isTrue);
    });

    test('applies comment strip per segment', () {
      final content = '''// header
int x = 1; // inline
/* block */
String url = "http://ex" + "ample"; // keep string
''';
      final issues = [
        {'file': path, 'line': 2},
      ];
      final out = buildSelectivePreview(
        path: path,
        content: content,
        issues: issues,
        headLines: 1,
        context: 2,
        maxChars: 1000,
      );
      // No starting line comments
      expect(RegExp(r'^\s*//', multiLine: true).hasMatch(out), isFalse);
      // Block comments removed
      expect(out.contains('/*'), isFalse);
      // Code lines still there
      expect(out.contains('int x = 1;'), isTrue);
      // Strings preserved
      expect(out.contains('http://ex'), isTrue);
    });

    test('respects maxChars cut', () {
      final content = List.filled(500, 'a').join();
      final issues = <Map<String, dynamic>>[];
      final out = buildSelectivePreview(
        path: path,
        content: content,
        issues: issues,
        headLines: 5,
        context: 2,
        maxChars: 120,
      );
      expect(out.length <= 120, isTrue);
    });
  });
}
