import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_summarizer/core/structured_content_parser.dart';

void main() {
  group('StructuredContentParser', () {
    test('accepts Map<String, dynamic> as is', () {
      const parser = StructuredContentParser();
      final res = parser.parse({'summary': 'ok', 'items': [1, 2, 3]});
      expect(res.isValid, isTrue);
      expect(res.errors, isEmpty);
      expect(res.data, isNotNull);
      expect(res.data!['summary'], 'ok');
    });

    test('decodes JSON string to Map', () {
      const parser = StructuredContentParser();
      final res = parser.parse('{"summary":"ok"}');
      expect(res.isValid, isTrue);
      expect(res.errors, isEmpty);
      expect(res.data, isNotNull);
      expect(res.data!['summary'], 'ok');
    });

    test('invalid type returns error', () {
      const parser = StructuredContentParser();
      final res = parser.parse([1, 2, 3]);
      expect(res.isValid, isFalse);
      expect(res.errors, isNotEmpty);
      expect(res.data, isNull);
    });

    test('adds warning when summary is not string', () {
      const parser = StructuredContentParser();
      final res = parser.parse({'summary': 123});
      expect(res.isValid, isTrue);
      expect(res.warnings, isNotEmpty);
    });
  });
}
