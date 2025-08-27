/// Utilities to parse simple unified diffs into per-file patches.
/// Scope: handles standard headers (--- a/{path}, +++ b/{path}) and groups
/// hunks by file. The body is preserved as-is; application may reconstruct
/// new content or use a simplified PatchApplyService strategy.
library unified_diff_utils;

class UnifiedFilePatch {
  final String path;
  final String diff;
  const UnifiedFilePatch({required this.path, required this.diff});
}

/// Parses raw unified diff into a list of per-file patches.
/// Limitations:
/// - Assumes file headers appear as pairs of lines: `--- a/<path>` then `+++ b/<path>`.
/// - Collects all subsequent lines as part of the same file diff until the next `--- a/`.
/// - If headers are malformed, that section is skipped.
List<UnifiedFilePatch> parseUnifiedDiffByFile(String raw) {
  final lines = raw.split('\n');
  final patches = <UnifiedFilePatch>[];

  String? currentPath;
  final currentBuf = StringBuffer();
  bool inFile = false;

  void flush() {
    if (inFile && currentPath != null) {
      final content = currentBuf.toString().trimRight();
      if (content.trim().isNotEmpty) {
        patches.add(UnifiedFilePatch(path: currentPath!, diff: content));
      }
    }
    currentPath = null;
    inFile = false;
    currentBuf.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('--- a/')) {
      // Next line should be +++ b/<path>
      // Flush previous file if any
      flush();
      final nextIdx = i + 1 < lines.length ? i + 1 : -1;
      if (nextIdx == -1) break;
      final next = lines[nextIdx];
      if (!next.startsWith('+++ b/')) {
        // malformed header, skip this '---' and continue
        continue;
      }
      // Determine path from +++ b/<path>
      final path = next.substring('+++ b/'.length);
      currentPath = path;
      inFile = true;
      // Start current buffer with both header lines
      currentBuf.writeln(line);
      currentBuf.writeln(next);
      // Skip the +++ line in the main loop by advancing i
      i = nextIdx;
      continue;
    }

    if (inFile) {
      currentBuf.writeln(line);
    }
  }

  // Flush tail
  flush();
  return patches;
}
