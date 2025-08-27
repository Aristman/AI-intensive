import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/utils/diff_view_utils.dart';

void main() {
  group('splitUnifiedDiffIntoSections', () {
    test('returns header-only when no hunks', () {
      const diff = 'diff --git a/file b/file\n--- a/file\n+++ b/file\n';
      final sections = splitUnifiedDiffIntoSections(diff);
      expect(sections.length, 1);
      expect(sections.first.title, 'Header');
      expect(sections.first.lines.join('\n'), contains('--- a/file'));
      expect(sections.first.lines.join('\n'), contains('+++ b/file'));
    });

    test('splits into header and hunks', () {
      const diff = 'diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,2 +1,2 @@\n-line1\n+line1_mod\n ctx\n@@ -10,0 +11,1 @@\n+added\n';
      final sections = splitUnifiedDiffIntoSections(diff);
      expect(sections.length, 3); // Header + 2 hunks
      expect(sections.first.title, 'Header');
      expect(sections[1].title.startsWith('@@'), isTrue);
      expect(sections[2].title.startsWith('@@'), isTrue);
      expect(sections[1].lines.first.startsWith('-') || sections[1].lines.first.startsWith('+') || sections[1].lines.first.isEmpty, isTrue);
    });

    test('handles empty string', () {
      final sections = splitUnifiedDiffIntoSections('');
      expect(sections, isEmpty);
    });
  });
}
