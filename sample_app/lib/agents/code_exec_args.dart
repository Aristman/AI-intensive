library code_exec_args;

Map<String, dynamic> buildDockerExecJavaArgs({
  required String code,
  String? filename,
  String? entrypoint,
  String? classpath,
  List<String>? compileArgs,
  List<String>? runArgs,
  String? image,
  String? containerName,
  String? extraArgs,
  String workdir = '/work',
  int timeoutMs = 15000,
  int? cpus,
  String? memory,
  String cleanup = 'always', // 'always' | 'on_success' | 'never'
}) {
  // Infer class and package to correct common mistakes (e.g., entrypoint="main").
  final inferredClass = _inferPublicClassName(code) ?? _inferClassFromFilename(filename);
  final inferredPackage = _inferPackageName(code);

  // Build effective filename: match package path if present, else use provided or ClassName.java
  final effectiveFilename = (() {
    if (inferredClass != null) {
      if (inferredPackage != null && inferredPackage.isNotEmpty) {
        final pkgPath = inferredPackage.replaceAll('.', '/');
        return '$pkgPath/$inferredClass.java';
      }
      return '${inferredClass}.java';
    }
    return (filename == null || filename.isEmpty) ? 'Main.java' : filename;
  })();

  // Build effective entrypoint: if provided and not 'main', use it; otherwise infer from class/package.
  final ep = (() {
    final given = entrypoint?.trim();
    if (given != null && given.isNotEmpty && given.toLowerCase() != 'main') {
      return given;
    }
    if (inferredClass != null) {
      return (inferredPackage != null && inferredPackage.isNotEmpty)
          ? '$inferredPackage.$inferredClass'
          : inferredClass;
    }
    return null; // leave unset if we couldn't infer reliably
  })();

  final args = <String, dynamic>{
    'filename': effectiveFilename,
    'code': code,
    if (ep != null && ep.isNotEmpty) 'entrypoint': ep,
    if (classpath != null && classpath.isNotEmpty) 'classpath': classpath,
    if (compileArgs != null) 'compile_args': compileArgs,
    if (runArgs != null) 'run_args': runArgs,
    if (image != null && image.isNotEmpty) 'image': image,
    if (containerName != null && containerName.isNotEmpty) 'container_name': containerName,
    if (extraArgs != null && extraArgs.isNotEmpty) 'extra_args': extraArgs,
    if (workdir.isNotEmpty) 'workdir': workdir,
    'timeout_ms': timeoutMs,
    'cleanup': cleanup,
  };
  if (cpus != null || memory != null) {
    args['limits'] = {
      if (cpus != null) 'cpus': cpus,
      if (memory != null && memory.isNotEmpty) 'memory': memory,
    };
  }
  return args;
}

String? _inferPackageName(String code) {
  final pkgRe = RegExp(r'package\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*;');
  final m = pkgRe.firstMatch(code);
  return m == null ? null : m.group(1);
}

String? _inferPublicClassName(String code) {
  final clsRe = RegExp(r'public\s+class\s+([A-Za-z_]\w*)');
  final m = clsRe.firstMatch(code);
  return m == null ? null : m.group(1);
}

String? _inferClassFromFilename(String? filename) {
  if (filename == null || filename.isEmpty) return null;
  // strip path and .java
  final slash = filename.lastIndexOf('/');
  final back = filename.lastIndexOf('\\');
  final cut = [slash, back].where((i) => i >= 0).fold(-1, (a, b) => a > b ? a : b);
  final base = filename.substring(cut + 1);
  if (!base.toLowerCase().endsWith('.java')) return null;
  return base.substring(0, base.length - 5);
}
