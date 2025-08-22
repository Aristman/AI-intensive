library;

/// Remove a single triple-backtick fenced block wrapper if present.
String stripCodeFencesGlobal(String text) {
  final t = text.trim();
  if (!t.contains('```')) return t;
  final start = t.indexOf('```');
  if (start == -1) return t;
  final end = t.indexOf('```', start + 3);
  if (end == -1) return t;
  var inner = t.substring(start + 3, end);
  final firstNl = inner.indexOf('\n');
  if (firstNl > -1) {
    final firstLine = inner.substring(0, firstNl).trim();
    if (firstLine.isNotEmpty && firstLine.length < 20) {
      inner = inner.substring(firstNl + 1);
    }
  }
  return inner.trim();
}

String? inferPackageName(String code) {
  final pkgRe = RegExp(r'package\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*;');
  final m = pkgRe.firstMatch(code);
  return m?.group(1);
}

String? inferPublicClassName(String code) {
  final clsRe = RegExp(r'public\s+class\s+([A-Za-z_]\w*)');
  final m = clsRe.firstMatch(code);
  return m?.group(1);
}

String basenameNoExt(String path) {
  final slash = path.lastIndexOf('/');
  final back = path.lastIndexOf('\\');
  final cut = [slash, back].where((i) => i >= 0).fold(-1, (a, b) => a > b ? a : b);
  final base = path.substring(cut + 1);
  return base.toLowerCase().endsWith('.java') ? base.substring(0, base.length - 5) : base;
}

String? fqcnFromFile(Map<String, String> f) {
  final raw = f['content'] ?? '';
  final code = stripCodeFencesGlobal(raw);
  final pkg = inferPackageName(code);
  final cls = inferPublicClassName(code) ?? basenameNoExt(f['path'] ?? 'Main.java');
  if (pkg != null && pkg.isNotEmpty) return '$pkg.$cls';
  return cls;
}

bool isTestContent(String code) {
  final t = code;
  return t.contains('org.junit') || t.contains('@Test');
}

bool isTestFile(Map<String, String> f) {
  final path = (f['path'] ?? '').trim();
  final name = basenameNoExt(path);
  if (name.endsWith('Test')) return true;
  final code = stripCodeFencesGlobal(f['content'] ?? '');
  return isTestContent(code);
}

/// Collect minimal set of files to run a JUnit test: the test itself and
/// its paired source class if found among pendingFiles.
/// Returns a map: { 'files': List of maps (String->String), 'entrypoint': String }
Map<String, dynamic> collectTestDeps({
  required Map<String, String> testFile,
  required List<Map<String, String>>? pendingFiles,
}) {
  final testClean = stripCodeFencesGlobal(testFile['content'] ?? '');
  final testFqcn = fqcnFromFile(testFile);
  if (testFqcn == null || testFqcn.isEmpty) {
    throw StateError('Не удалось определить FQCN тестового класса');
  }
  final files = <Map<String, String>>[
    {
      'path': testFile['path'] ?? 'Test.java',
      'content': testClean,
    },
  ];

  Map<String, String>? srcFile;
  try {
    final pkg = inferPackageName(testClean);
    final testCls = inferPublicClassName(testClean) ?? basenameNoExt(testFile['path'] ?? 'Test.java');
    String? baseName;
    if (testCls.endsWith('Test')) {
      baseName = testCls.substring(0, testCls.length - 4);
    }
    if (baseName != null && baseName.isNotEmpty && pendingFiles != null && pendingFiles.isNotEmpty) {
      final expectedRel = (pkg != null && pkg.isNotEmpty)
          ? '${pkg.replaceAll('.', '/')}/$baseName.java'
          : '$baseName.java';
      for (final f in pendingFiles) {
        final p = (f['path'] ?? '').trim();
        if (p == expectedRel || p.endsWith('/$expectedRel') || p.endsWith('\\$expectedRel')) {
          srcFile = f;
          break;
        }
      }
      if (srcFile == null) {
        for (final f in pendingFiles) {
          final content = stripCodeFencesGlobal(f['content'] ?? '');
          final pkg2 = inferPackageName(content);
          final cls2 = inferPublicClassName(content) ?? basenameNoExt(f['path'] ?? 'Main.java');
          if (cls2 == baseName && pkg2 == pkg) {
            srcFile = f;
            break;
          }
        }
      }
    }
  } catch (_) {
    // ignore
  }

  if (srcFile != null) {
    files.add({
      'path': srcFile['path'] ?? 'Main.java',
      'content': stripCodeFencesGlobal(srcFile['content'] ?? ''),
    });
  }

  return {
    'files': files,
    'entrypoint': testFqcn,
  };
}
