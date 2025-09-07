class FilePreview {
  final String path;
  final bool exists;
  final bool isDir;
  final int size;
  final String contentSnippet;
  final String message;

  const FilePreview({
    required this.path,
    required this.exists,
    required this.isDir,
    required this.size,
    required this.contentSnippet,
    required this.message,
  });
}

class FileOpResult {
  final bool success;
  final String path;
  final int bytesWritten;
  final String message;

  const FileOpResult({
    required this.success,
    required this.path,
    required this.bytesWritten,
    required this.message,
  });
}

class DirEntry {
  final String name;
  final bool isDir;
  final int? size; // null for dirs

  const DirEntry({required this.name, required this.isDir, this.size});
}

class DirListing {
  final String path;
  final List<DirEntry> entries;
  final String? message; // optional status/info

  const DirListing({required this.path, required this.entries, this.message});

  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('Каталог: $path');
    if (message != null && message!.isNotEmpty) {
      buf.writeln(message);
    }
    if (entries.isEmpty) {
      buf.writeln('(пусто)');
      return buf.toString().trim();
    }
    for (final e in entries) {
      final mark = e.isDir ? '[DIR]' : '[FILE]';
      final sizeStr = e.isDir ? '' : ' (${e.size} bytes)';
      buf.writeln('- $mark ${e.name}$sizeStr');
    }
    return buf.toString().trim();
  }
}
