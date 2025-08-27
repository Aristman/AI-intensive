import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/utils/token_estimator.dart';

void main() {
  group('token_estimator', () {
    test('estimateTokensForText grows with size', () {
      final small = estimateTokensForText('abcd'); // ~1 token
      final bigger = estimateTokensForText(List.filled(400, 'a').join()); // ~100 tokens
      expect(bigger, greaterThan(small));
    });

    test('empty string -> 0', () {
      expect(estimateTokensForText(''), 0);
    });

    test('estimateTokensByChars aligns roughly with text estimator', () {
      final text = List.filled(800, 'x').join();
      final e1 = estimateTokensForText(text);
      final e2 = estimateTokensByChars(text.length, lines: 1);
      // Must be within reasonable range
      expect((e1 - e2).abs() < 30, isTrue);
    });
  });
}
