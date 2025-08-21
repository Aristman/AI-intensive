import 'dart:convert';

/// Tries to extract a JSON object (Map) from arbitrary text.
/// Handles plain JSON, fenced blocks ```json ... ``` and text with embedded JSON.
Map<String, dynamic>? tryExtractJsonMap(String text) {
  String s = text.trim();

  Map<String, dynamic>? tryDecode(String candidate) {
    try {
      final v = jsonDecode(candidate);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return null;
  }

  // 1) Direct attempt
  final direct = tryDecode(s);
  if (direct != null) return direct;

  // 2) Strip code fences ```...```
  if (s.contains('```')) {
    final start = s.indexOf('```');
    if (start != -1) {
      final end = s.indexOf('```', start + 3);
      if (end != -1) {
        var inner = s.substring(start + 3, end).trim();
        // Drop language hint line like "json"
        final firstNl = inner.indexOf('\n');
        if (firstNl > -1) {
          final firstLine = inner.substring(0, firstNl).trim().toLowerCase();
          if (firstLine.isNotEmpty && firstLine.length <= 10) {
            // treat as language hint
            inner = inner.substring(firstNl + 1);
          }
        }
        final fenced = tryDecode(inner.trim());
        if (fenced != null) return fenced;
      }
    }
  }

  // 3) Try to grab substring between first '{' and last '}'
  final l = s.indexOf('{');
  final r = s.lastIndexOf('}');
  if (l >= 0 && r > l) {
    final sub = s.substring(l, r + 1);
    final mid = tryDecode(sub);
    if (mid != null) return mid;
  }

  return null;
}
