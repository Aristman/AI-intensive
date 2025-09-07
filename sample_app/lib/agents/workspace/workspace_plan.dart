class PlanStep {
  final int id;
  final String title;
  bool done;

  PlanStep({required this.id, required this.title, this.done = false});
}

class Plan {
  final List<PlanStep> steps;
  DateTime updatedAt;

  Plan({List<PlanStep>? steps})
      : steps = steps ?? <PlanStep>[],
        updatedAt = DateTime.now();

  void addStep(String title) {
    final nextId = steps.isEmpty ? 1 : (steps.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1);
    steps.add(PlanStep(id: nextId, title: title));
    updatedAt = DateTime.now();
  }

  void addSteps(Iterable<String> titles) {
    for (final t in titles) {
      if (t.trim().isEmpty) continue;
      addStep(t.trim());
    }
  }

  void markDoneByIds(Iterable<int> ids) {
    final set = ids.toSet();
    for (final s in steps) {
      if (set.contains(s.id)) s.done = true;
    }
    updatedAt = DateTime.now();
  }

  void clear() {
    steps.clear();
    updatedAt = DateTime.now();
  }

  bool get isEmpty => steps.isEmpty;

  String renderMarkdown() {
    if (steps.isEmpty) return 'План пуст. Добавьте шаги или попросите составить план.';
    final buf = StringBuffer();
    buf.writeln('План задач:');
    for (final s in steps) {
      final mark = s.done ? 'x' : ' ';
      buf.writeln('- [$mark] ${s.id}. ${s.title}');
    }
    buf.writeln('\nОбновлён: ${updatedAt.toLocal()}');
    return buf.toString().trim();
  }

  /// Человекочитаемое представление плана.
  /// Преобразует технические шаги типа "write file <path>: <content>" в понятные пользователю формулировки.
  String renderHumanMarkdown() {
    if (steps.isEmpty) return 'План пуст. Добавьте шаги или попросите составить план.';
    final buf = StringBuffer();
    buf.writeln('План выполнения:');
    for (final s in steps) {
      final human = _humanizeStep(s.title);
      final mark = s.done ? 'x' : ' ';
      buf.writeln('- [$mark] ${s.id}. $human');
    }
    buf.writeln('\nОбновлён: ${updatedAt.toLocal()}');
    return buf.toString().trim();
  }

  String _humanizeStep(String raw) {
    final t = raw.trim();
    // create directory
    final mCreate = RegExp(r'^(?:создай|create)\s+directory\s+(.+)$', caseSensitive: false).firstMatch(t);
    if (mCreate != null) {
      final path = _sanitizePath(mCreate.group(1) ?? '');
      return 'Создать каталог: $path';
    }
    // write file
    final mWrite = RegExp(r'^(?:запиши\s+файл|write\s+file)\s+(.+?)\s*:\s*([\s\S]*)$', caseSensitive: false).firstMatch(t);
    if (mWrite != null) {
      final path = _sanitizePath(mWrite.group(1) ?? '');
      final content = (mWrite.group(2) ?? '').trim();
      final note = content.isEmpty ? ' (содержимое будет сгенерировано или задано далее)' : '';
      return 'Записать файл: $path$note';
    }
    // read file
    final mRead = RegExp(r'^(?:прочитай\s+файл|read\s+file)\s+(.+)$', caseSensitive: false).firstMatch(t);
    if (mRead != null) {
      final path = _sanitizePath(mRead.group(1) ?? '');
      return 'Прочитать файл: $path';
    }
    // list dir
    final mList = RegExp(r'^(?:список\s+файлов|list\s+dir)\s+(.+)$', caseSensitive: false).firstMatch(t);
    if (mList != null) {
      final path = _sanitizePath(mList.group(1) ?? '');
      return 'Показать содержимое каталога: $path';
    }
    // delete
    final mDel = RegExp(r'^(?:удали|delete)\s+(.+)$', caseSensitive: false).firstMatch(t);
    if (mDel != null) {
      final cmd = mDel.group(1)!.trim();
      final recursive = cmd.startsWith('-r ');
      final path = _sanitizePath(recursive ? cmd.substring(3).trim() : cmd);
      return recursive ? 'Удалить рекурсивно: $path' : 'Удалить: $path';
    }
    // generate code
    final mGen = RegExp(r'^(?:сгенерируй\s+код|создай\s+код|generate\s+code|create\s+code)\s+(.+?)\s*:\s+([\s\S]+)$', caseSensitive: false).firstMatch(t);
    if (mGen != null) {
      final lang = (mGen.group(1) ?? '').trim();
      final task = (mGen.group(2) ?? '').trim();
      return 'Сгенерировать код на $lang: $task';
    }
    // fallback
    return t[0].toUpperCase() + t.substring(1);
  }

  String _sanitizePath(String raw) {
    var p = raw.trim();
    p = p.replaceFirst(RegExp(r'\s*\(.*?\)\s*$'), '');
    if ((p.startsWith('"') && p.endsWith('"')) || (p.startsWith("'") && p.endsWith("'"))) {
      p = p.substring(1, p.length - 1);
    }
    return p.trim();
  }
}
