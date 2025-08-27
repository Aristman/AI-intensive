import 'package:sample_app/domain/llm_resolver.dart';
import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/models/app_settings.dart';

/// Результат применения диффа с информацией о токенах
class DiffApplyResult {
  final String? content;
  final Map<String, int>? tokens;
  
  const DiffApplyResult({this.content, this.tokens});
}

/// Агент, применяющий unified diff к исходному файлу при помощи LLM.
/// Возвращает итоговое содержимое файла и информацию о токенах.
class DiffApplyAgent {
  final LlmUseCase? _useCase;
  DiffApplyAgent({LlmUseCase? useCase}) : _useCase = useCase;

  Future<DiffApplyResult> apply({
    required String original,
    required String diff,
    required AppSettings settings,
  }) async {
    // 1) Попытка локального применения простого диффа «полная замена файла».
    final locallyApplied = _tryApplyFullFileUnifiedDiff(original: original, diff: diff);
    if (locallyApplied != null) {
      // Экономим токены: LLM не вызывался
      return DiffApplyResult(content: locallyApplied, tokens: null);
    }

    // 2) Fallback к LLM
    final uc = _useCase ?? resolveLlmUseCase(settings);
    final system =
        'Ты помощник по модификации кода. Тебе дан исходный файл и unified diff. '
        'Не объясняй. Верни только финальное содержимое файла после применения диффа. '
        'Строго никаких комментариев вне кода.';

    final prompt = StringBuffer()
      ..writeln('Ниже исходный файл в блоке ```orig``` и diff в блоке ```diff```.')
      ..writeln('Применись дифф к исходному и верни только финальный файл в блоке без языка:')
      ..writeln('```')
      ..writeln('...здесь должен быть только финальный файл...')
      ..writeln('```')
      ..writeln('Исходный файл:')
      ..writeln('```orig')
      ..writeln(original)
      ..writeln('```')
      ..writeln('Дифф:')
      ..writeln('```diff')
      ..writeln(diff)
      ..writeln('```');

    final response = await uc.completeWithUsage(messages: [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': prompt.toString()},
    ], settings: settings);

    // Извлекаем первый безъязыковый блок ```...``` либо первый код-блок вообще.
    final content = _extractCodeFence(response.text) ?? response.text.trim();
    final resultContent = content.isEmpty ? null : content;
    
    return DiffApplyResult(
      content: resultContent,
      tokens: response.usage,
    );
  }

  String? _extractCodeFence(String text) {
    // Ищем тройные бэктики
    final re = RegExp(r"```[a-zA-Z0-9_-]*\n([\s\S]*?)\n```", multiLine: true);
    final m = re.firstMatch(text);
    if (m != null) {
      return m.group(1)?.trim();
    }
    return null;
  }

  /// Пытается применить простой unified diff формата одной «цельной» замены файла,
  /// который генерирует `_makeUnifiedDiff()` в `auto_fix_agent.dart`.
  /// Ожидаемый формат:
  /// --- a/<path>\n
  /// +++ b/<path>\n
  /// @@ -1,<oldLen> +1,<newLen> @@\n
  /// -old line 1\n
  /// ...\n
  /// +new line 1\n
  /// ...
  /// Возвращает новое содержимое или null, если формат не распознан.
  String? _tryApplyFullFileUnifiedDiff({required String original, required String diff}) {
    final lines = diff.split('\n');
    if (lines.length < 4) return null;
    if (!lines[0].startsWith('--- a/')) return null;
    if (!lines[1].startsWith('+++ b/')) return null;
    if (!lines[2].startsWith('@@ -1,')) return null;

    // Проверим, что хедер хунка начинается с +1,
    // это характерно для полной замены, которую мы генерируем.
    final hunkHeader = lines[2];
    if (!hunkHeader.contains(' +1,')) return null;

    // Не поддерживаем множественные хунки для локального применения.
    for (var i = 3; i < lines.length; i++) {
      if (lines[i].startsWith('@@')) return null;
    }

    // Извлечём ожидаемую длину нового файла из заголовка: @@ -1,old +1,new @@
    final m = RegExp(r"\+1,(\d+)").firstMatch(hunkHeader);
    if (m == null) return null;
    final expectedNewLen = int.tryParse(m.group(1)!);
    if (expectedNewLen == null) return null;

    // Соберём новые строки: те, что начинаются с '+', исключая заголовки.
    final newBuf = StringBuffer();
    var plusCount = 0;
    for (var i = 3; i < lines.length; i++) {
      final l = lines[i];
      if (l.startsWith('+++ ') || l.startsWith('--- ') || l.startsWith('@@')) {
        continue; // заголовки
      }
      // Если присутствуют контекстные строки (начинаются с пробела), это не полная замена
      if (l.isNotEmpty && !l.startsWith('+') && !l.startsWith('-')) {
        return null;
      }
      if (l.startsWith('+')) {
        newBuf.writeln(l.substring(1));
        plusCount++;
      }
    }
    final newContent = newBuf.toString();
    if (newContent.isEmpty) return null; // не похоже на полную замену
    if (plusCount != expectedNewLen) return null; // количество строк не сходится с заявленной длиной
    return newContent;
  }
}
