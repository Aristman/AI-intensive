import 'package:test/test.dart';
import 'package:sample_app/utils/json_utils.dart';

void main() {
  group('tryExtractJsonMap', () {
    test('parses plain JSON object', () {
      final input = '{"a":1, "b":"str"}';
      final res = tryExtractJsonMap(input);
      expect(res, isA<Map<String, dynamic>>());
      expect(res!['a'], 1);
      expect(res['b'], 'str');
    });

    test('parses fenced json block with language', () {
      final input = '```json\n{"x":2}\n```';
      final res = tryExtractJsonMap(input);
      expect(res, isNotNull);
      expect(res!['x'], 2);
    });

    test('parses fenced block without language', () {
      final input = '```\n{"ok":true}\n```';
      final res = tryExtractJsonMap(input);
      expect(res, isNotNull);
      expect(res!['ok'], true);
    });

    test('parses embedded fenced json inside text', () {
      final input = 'Here is data:\n```json\n{"k":"v"}\n```\nThanks';
      final res = tryExtractJsonMap(input);
      expect(res, isNotNull);
      expect(res!['k'], 'v');
    });

    test('parses substring between braces when mixed text', () {
      final input = 'prefix {"n": 42} suffix';
      final res = tryExtractJsonMap(input);
      expect(res, isNotNull);
      expect(res!['n'], 42);
    });

    test('returns null for invalid json', () {
      final input = 'not a json and no braces';
      final res = tryExtractJsonMap(input);
      expect(res, isNull);
    });
  });
}
