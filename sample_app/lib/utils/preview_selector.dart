library preview_selector;

import 'code_strip.dart';

/// Build selective preview for a file based on issues:
/// - headLines from file start
/// - for each issue with `line` (1-based), include a window of `context` lines around it
/// - de-duplicate overlapping windows
/// - slice by ORIGINAL content, then strip per segment (to keep issue line alignment)
String buildSelectivePreview({
  required String path,
  required String content,
  required List<Map<String, dynamic>> issues,
  int headLines = 40,
  int context = 10,
  int maxChars = 800,
}) {
  final origLines = content.split('\n');

  // Collect windows (1-based indices)
  final windows = <_Win>[];
  // Head
  final headEnd = headLines.clamp(0, origLines.length);
  if (headEnd > 0) windows.add(_Win(1, headEnd));

  // Around issues
  for (final it in issues) {
    final line = it['line'];
    if (line is int && line > 0) {
      final start = (line - context).clamp(1, origLines.length);
      final end = (line + context).clamp(1, origLines.length);
      windows.add(_Win(start, end));
    }
  }

  if (windows.isEmpty) {
    // Fallback to head-only by chars after stripping
    final stripped = stripCommentsForPath(path, content);
    return stripped.length > maxChars ? stripped.substring(0, maxChars) : stripped;
  }

  // Merge windows
  windows.sort((a, b) => a.start.compareTo(b.start));
  final merged = <_Win>[];
  for (final w in windows) {
    if (merged.isEmpty) {
      merged.add(w);
    } else {
      final last = merged.last;
      if (w.start <= last.end + 1) {
        last.end = w.end > last.end ? w.end : last.end;
      } else {
        merged.add(_Win(w.start, w.end));
      }
    }
  }

  // Build preview with separators, strip each segment
  final sb = StringBuffer();
  for (var i = 0; i < merged.length; i++) {
    final w = merged[i];
    final segOrig = origLines.sublist(w.start - 1, w.end).join('\n');
    final seg = stripCommentsForPath(path, segOrig);
    if (sb.isNotEmpty) sb.writeln('\n...');
    sb.writeln(seg);
  }

  var out = sb.toString();
  if (out.length > maxChars) {
    out = out.substring(0, maxChars);
  }
  return out;
}

class _Win {
  int start;
  int end;
  _Win(this.start, this.end);
}
