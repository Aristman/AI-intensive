library file_preview_cache;

class FilePreviewCache {
  static final FilePreviewCache instance = FilePreviewCache._();
  FilePreviewCache._();

  final Map<String, _Entry> _map = {};

  static String makeSignature({required String content, int? mtimeMs}) {
    // Simple signature: length + Dart hashCode + optional mtime
    final len = content.length;
    final h = content.hashCode;
    final mt = mtimeMs ?? 0;
    return '$len:$h:$mt';
  }

  static String makeIssuesKey(List<Map<String, dynamic>> issues) {
    if (issues.isEmpty) return '-';
    final parts = <String>[];
    for (final it in issues) {
      final t = it['type']?.toString() ?? '';
      final l = it['line']?.toString() ?? '';
      parts.add('$t@$l');
    }
    return parts.join('|');
  }

  bool shouldOmit(String path, String signature, String issuesKey) {
    final e = _map[path];
    if (e == null) return false;
    return e.signature == signature && e.issuesKey == issuesKey;
  }

  String? getCachedPreview(String path, String signature, String issuesKey) {
    final e = _map[path];
    if (e == null) return null;
    if (e.signature == signature && e.issuesKey == issuesKey) return e.preview;
    return null;
  }

  void store(String path, String signature, String issuesKey, String preview) {
    _map[path] = _Entry(signature, issuesKey, preview);
  }

  void clear() => _map.clear();
}

class _Entry {
  final String signature;
  final String issuesKey;
  final String preview;
  _Entry(this.signature, this.issuesKey, this.preview);
}
