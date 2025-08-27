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
}
