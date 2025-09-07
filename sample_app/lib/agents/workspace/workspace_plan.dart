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
}
