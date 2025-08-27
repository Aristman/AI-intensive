import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/utils/file_preview_cache.dart';

void main() {
  group('file_preview_cache', () {
    const path = 'lib/a.dart';

    setUp(() {
      FilePreviewCache.instance.clear();
    });

    test('store and omit unchanged with same issues', () {
      final content = 'int a = 1;\n';
      final sig = FilePreviewCache.makeSignature(content: content, mtimeMs: 123);
      final issues = [
        {'type': 'warn', 'line': 2},
      ];
      final key = FilePreviewCache.makeIssuesKey(issues);

      expect(FilePreviewCache.instance.shouldOmit(path, sig, key), isFalse);
      FilePreviewCache.instance.store(path, sig, key, '<preview>');
      expect(FilePreviewCache.instance.shouldOmit(path, sig, key), isTrue);
      expect(FilePreviewCache.instance.getCachedPreview(path, sig, key), '<preview>');

      // Change signature -> not omitted
      final sig2 = FilePreviewCache.makeSignature(content: content + 'x', mtimeMs: 123);
      expect(FilePreviewCache.instance.shouldOmit(path, sig2, key), isFalse);

      // Change issues -> not omitted
      final key2 = FilePreviewCache.makeIssuesKey([
        {'type': 'warn', 'line': 3},
      ]);
      expect(FilePreviewCache.instance.shouldOmit(path, sig, key2), isFalse);
    });
  });
}
