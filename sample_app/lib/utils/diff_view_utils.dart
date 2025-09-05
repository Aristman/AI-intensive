// Utility for splitting unified diff text into sections (header + hunks)
// This is UI-agnostic and can be unit-tested.

class DiffSection {
  final String title; // e.g., "Header" or @@ -a,+b @@
  final List<String> lines; // raw lines including +/-/space

  const DiffSection({required this.title, required this.lines});
}

/// Splits a unified diff into logical sections:
/// - Optional header (lines before first hunk starting with '@@')
/// - One section per hunk (title is the '@@ ... @@' line)
///
/// The function is conservative and does not validate diff semantics.
List<DiffSection> splitUnifiedDiffIntoSections(String diff) {
  if (diff.trim().isEmpty) return const <DiffSection>[];
  final lines = diff.split(RegExp(r'\r?\n'));
  final sections = <DiffSection>[];
  final header = <String>[];

  String? currentTitle;
  List<String>? currentLines;

  void flushCurrent() {
    if (currentTitle != null && currentLines != null) {
      sections.add(DiffSection(title: currentTitle!, lines: List.unmodifiable(currentLines!)));
    }
    currentTitle = null;
    currentLines = null;
  }

  for (final raw in lines) {
    final line = raw; // keep as-is
    if (line.startsWith('@@')) {
      // start new hunk
      if (currentTitle == null && header.isNotEmpty) {
        // flush header as a section once we see the first hunk
        sections.add(DiffSection(title: 'Header', lines: List.unmodifiable(header)));
        header.clear();
      }
      flushCurrent();
      currentTitle = line.trim().isEmpty ? '@@' : line;
      currentLines = <String>[];
    } else {
      if (currentTitle == null) {
        header.add(line);
      } else {
        currentLines!.add(line);
      }
    }
  }

  // finalize
  flushCurrent();
  if (sections.isEmpty && header.isNotEmpty) {
    // diff without hunks -> single header-only section
    sections.add(DiffSection(title: 'Header', lines: List.unmodifiable(header)));
  }
  return List.unmodifiable(sections);
}
