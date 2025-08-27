/// Very rough token estimator for prompting.
/// Heuristic: ~4 chars per token for mixed code/text.
/// Use only for budgeting to downscale previews/files.
library token_estimator;

int estimateTokensForText(String text) {
  if (text.isEmpty) return 0;
  // Count characters; divide by 4 and add small overhead per line.
  final chars = text.length;
  final lines = _countLines(text);
  final base = (chars / 4).ceil();
  final overhead = (lines * 0.2).ceil();
  return base + overhead;
}

int _countLines(String s) => s.isEmpty ? 0 : RegExp('\n').allMatches(s).length + 1;

int estimateTokensByChars(int chars, {int lines = 0}) {
  final base = (chars / 4).ceil();
  final overhead = (lines * 0.2).ceil();
  return base + overhead;
}
