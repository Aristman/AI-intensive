import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/utils/code_strip.dart';

void main() {
  group('code_strip', () {
    test('strips // line and /* */ block comments for .dart', () {
      const path = 'lib/a.dart';
      const src = '''
// file header
int x = 1; // inline
/* block
   comment */
String s = "http://example.com"; // not a comment inside string (heuristic)
''';
      final out = stripCommentsForPath(path, src);
      // No line comments at line starts
      expect(RegExp(r'^\s*//', multiLine: true).hasMatch(out), isFalse);
      expect(out.contains('/*'), isFalse);
      expect(out.contains('comment */'), isFalse);
      expect(out.contains('int x = 1;'), isTrue);
      expect(out.contains('String s = "http://example.com";'), isTrue);
    });

    test('strips for .java', () {
      const path = 'A.java';
      const src = 'int a; // t\n/*b*/\nint b;\n';
      final out = stripCommentsForPath(path, src);
      expect(RegExp(r'^\s*//', multiLine: true).hasMatch(out), isFalse);
      expect(out.contains('/*'), isFalse);
      expect(out.contains('int a;'), isTrue);
      expect(out.contains('int b;'), isTrue);
    });

    test('strips HTML comments and collapses blanks for .md', () {
      const path = 'README.md';
      const src = '''# Title

<!-- secret -->

Paragraph.


Another.
''';
      final out = stripCommentsForPath(path, src);
      expect(out.contains('<!--'), isFalse);
      // At most two consecutive blanks preserved
      expect(RegExp(r"\n\n\n").hasMatch(out), isFalse);
      expect(out.contains('Title'), isTrue);
      expect(out.contains('Paragraph.'), isTrue);
      expect(out.contains('Another.'), isTrue);
    });
  });
}
