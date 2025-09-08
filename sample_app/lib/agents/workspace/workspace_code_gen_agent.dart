import 'dart:developer' as dev;

import 'package:sample_app/agents/agent_interface.dart';
import 'package:sample_app/domain/llm_resolver.dart';
import 'package:sample_app/models/app_settings.dart';

/// WorkspaceCodeGenAgent — простой агент генерации кода по заданию и языку.
/// Вход:
/// - req.context['language'] (String)
/// - req.context['task'] (String)
/// Либо строка input формата: "generate code <lang>: <task>" или "сгенерируй код <lang>: <task>".
/// Выход: форматированный текст кода (желательно в fenced-блоке), готовый к записи в файл.
class WorkspaceCodeGenAgent with AuthPolicyMixin implements IAgent {
  AppSettings _settings;

  WorkspaceCodeGenAgent({AppSettings? baseSettings}) : _settings = baseSettings ?? const AppSettings();

  @override
  AgentCapabilities get capabilities => const AgentCapabilities(
        stateful: false,
        streaming: false,
        reasoning: true,
        tools: {},
        systemPrompt: 'You are a senior software engineer generating production-ready code.',
        responseRules: [
          'Всегда добавляй все необходимые импорты явно',
          'Выдавай только код без пояснений, по возможности в одном цельном блоке',
          'Никогда не используй Markdown и тройные бэктики (```)',
        ],
      );

  @override
  Future<AgentResponse> ask(AgentRequest req) async {
    await ensureAuthorized(req, action: 'ask');

    // 1) Извлекаем language/task из контекста или парсим из input
    String? language = req.context != null ? req.context!['language']?.toString() : null;
    String? task = req.context != null ? req.context!['task']?.toString() : null;
    if (language == null || task == null) {
      final parsed = _parseInput(req.input);
      language = language ?? parsed.$1;
      task = task ?? parsed.$2;
    }

    // 2) Уточнения, если не хватает данных
    if (language == null || language.trim().isEmpty) {
      final msg = 'Пожалуйста, укажите язык программирования. Пример: "сгенерируй код Dart: виджет кнопки".';
      return AgentResponse(text: msg, isFinal: false);
    }
    if (task == null || task.trim().isEmpty) {
      final msg = 'Пожалуйста, опишите задачу для генерации кода. Пример: "сгенерируй код Dart: функция суммирования".';
      return AgentResponse(text: msg, isFinal: false);
    }

    // 3) Формируем строгий системный промпт под генерацию кода
    final sys = _buildSystemPrompt(language: language);

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': sys},
      {
        'role': 'user',
        'content': 'Сгенерируй законченный код на языке "$language" для задачи: $task\n'
            'Важно: включи все необходимые импорты/using/package, соблюдай каноны языка. '
            'Строго: не используй Markdown и тройные бэктики, выведи только код без пояснений.\n'
      },
    ];

    try {
      final sw = Stopwatch()..start();
      final usecase = resolveLlmUseCase(_settings);
      var text = await usecase.complete(messages: messages, settings: _settings);

      // Нормализуем: убираем лишние завершающие токены, если где-то используются
      const stopToken = '<<END>>'; // не используется глобально, просто страховка
      if (text.contains(stopToken)) {
        text = text.replaceAll(stopToken, '').trim();
      }

      sw.stop();
      dev.log('Code generated for lang=$language in ${sw.elapsedMilliseconds} ms, size=${text.length}',
          name: 'WorkspaceCodeGenAgent');

      // Возвращаем ровно текст кода. Если LLM вернул fenced-блок — оставляем как есть.
      return AgentResponse(
        text: text.trim(),
        isFinal: true,
        mcpUsed: false,
        meta: {
          'language': language,
          'durationMs': sw.elapsedMilliseconds,
          'task': task,
        },
      );
    } catch (e) {
      final err = 'Ошибка генерации кода: $e';
      return AgentResponse(text: err, isFinal: true, mcpUsed: false, meta: {'error': e.toString()});
    }
  }

  @override
  Stream<AgentEvent>? start(AgentRequest req) => null; // без стриминга

  @override
  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  @override
  void dispose() {}

  // ==== Helpers ====
  (String?, String?) _parseInput(String raw) {
    final t = raw.trim();
    // RU: "сгенерируй код <lang>: <task>" | "создай код <lang>: <task>"
    final ru = RegExp(r'^(?:сгенерируй\s+код|создай\s+код)\s+(.+?)\s*:\s+([\s\S]+)$', caseSensitive: false);
    final rm = ru.firstMatch(t);
    if (rm != null) {
      return (rm.group(1)?.trim(), rm.group(2)?.trim());
    }
    // EN: "generate code <lang>: <task>" | "create code <lang>: <task>"
    final en = RegExp(r'^(?:generate\s+code|create\s+code)\s+(.+?)\s*:\s+([\s\S]+)$', caseSensitive: false);
    final em = en.firstMatch(t);
    if (em != null) {
      return (em.group(1)?.trim(), em.group(2)?.trim());
    }
    return (null, null);
  }

  String _buildSystemPrompt({required String language}) {
    // Системные правила генерации кода — соответствуют нашим стандартам CodeOps
    final rules = [
      'Выдавай только законченный код без комментариев и пояснений',
      'Код должен быть рабочим и самодостаточным',
      'Все импорты и зависимости должны быть указаны явно',
      'Не добавляй текст вне кода, если не попросили',
      'Запрещено использовать Markdown и тройные бэктики (```)',
    ].join('\n- ');

    return [
      'Ты — опытный разработчик. Генерируешь чистый, рабочий код.',
      'Язык: $language',
      'Правила:\n- $rules',
    ].join('\n\n');
  }
}
