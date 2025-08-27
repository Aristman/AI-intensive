/// Simple comment stripper per file extension.
/// - .dart/.kt/.java: remove // line comments and /* */ block comments (naive regex)
/// - .md/.markdown: remove HTML comments <!-- --> and collapse blank lines
/// Note: This is a heuristic and may affect strings with comment-like content.
/// Use only for prompt-size reduction, not for source rewriting.
library code_strip;

String stripCommentsForPath(String path, String content) {
  final p = path.toLowerCase();
  if (p.endsWith('.dart') || p.endsWith('.kt') || p.endsWith('.java')) {
    return _stripCStyle(content);
  }
  if (p.endsWith('.md') || p.endsWith('.markdown')) {
    return _stripMarkdown(content);
  }
  return content;
}

String _stripCStyle(String input) {
  var text = input;
  // Remove block comments /* ... */ (non-greedy)
  text = text.replaceAll(RegExp(r"/\*[\s\S]*?\*/", multiLine: true), '');
  // Remove line comments // ... (to end of line)
  text = text.replaceAllMapped(RegExp(r"(^|\s)//.*", multiLine: true), (m) {
    final lead = m.group(1) ?? '';
    return lead; // preserve leading whitespace if any
  });
  // Trim trailing spaces and collapse multiple blank lines to at most 1
  final lines = text.split('\n').map((l) => l.replaceAll(RegExp(r"\s+$"), '')).toList();
  final out = <String>[];
  var blankCount = 0;
  for (final l in lines) {
    if (l.trim().isEmpty) {
      blankCount++;
      if (blankCount <= 1) out.add('');
    } else {
      blankCount = 0;
      out.add(l);
    }
  }
  return out.join('\n');
}

String _stripMarkdown(String input) {
  var text = input;
  // Remove HTML comments
  text = text.replaceAll(RegExp(r"<!--([\s\S]*?)-->", multiLine: true), '');
  // Collapse multiple blank lines to at most 1 to preserve structure but reduce tokens
  final lines = text.split('\n');
  final out = <String>[];
  var blankCount = 0;
  for (final l in lines) {
    if (l.trim().isEmpty) {
      blankCount++;
      if (blankCount <= 1) out.add('');
    } else {
      blankCount = 0;
      out.add(l.trimRight());
    }
  }
  return out.join('\n');
}
