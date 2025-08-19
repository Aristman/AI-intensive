import 'package:sample_app/agents/agent.dart' show Agent; // for stopSequence
import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/data/llm/deepseek_usecase.dart';
import 'package:sample_app/data/llm/yandexgpt_usecase.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/mcp_client.dart';
import 'package:sample_app/services/mcp_integration_service.dart';

/// Агент для кодовых операций (CodeOpsAgent)
/// - Хранит историю общения
/// - Умеет сжимать контекст (summary) через LLM, чтобы не выходить за лимит
/// - Ориентирован на работу с кодом (подсказки, диффы, ссылки на файлы)
/// - Может запускать локальный Docker с Java окружением через MCP (docker_start_java)
class CodeOpsAgent {
  static const String stopSequence = Agent.stopSequence;

  final List<_Msg> _history = [];
  String? _memory; // сжатая память (summary предыдущего контекста)

  AppSettings _settings;
  final McpIntegrationService _mcpIntegrationService;

  CodeOpsAgent({AppSettings? baseSettings})
      : _settings = (baseSettings ?? const AppSettings()).copyWith(
          reasoningMode: true,
          // По умолчанию текстовый ответ; JSON при необходимости через настройки
        ),
        _mcpIntegrationService = McpIntegrationService();

  void updateSettings(AppSettings s) {
    _settings = s.copyWith(reasoningMode: true);
  }

  void clearHistory() {
    _history.clear();
    _memory = null;
  }

  LlmUseCase _resolveUseCase() {
    switch (_settings.selectedNetwork) {
      case NeuralNetwork.deepseek:
        return DeepSeekUseCase();
      case NeuralNetwork.yandexgpt:
        return YandexGptUseCase();
    }
  }

  String _buildSystemContent({ResponseFormat? overrideResponseFormat, String? overrideJsonSchema}) {
    final codeOpsGuide =
        'Ты — инженерный агент, работающий с кодом и инфраструктурой. '
        'Всегда думай, как разработчик: ссылайся на файлы и директории в обратных кавычках, '
        'предлагай минимальные изменения, предпочитай патчи/диффы и конкретику. '
        'Если запрашивают команды — давай точные команды и указывай рабочую директорию. '
        'Если не хватает данных, задай уточняющие вопросы перед финальным ответом.';

    final uncertaintyPolicy = 'Политика уточнений: оцени неопределённость 0..1. '
        'Если > 0.1 — задай уточняющие вопросы, не давай финал и не добавляй маркер окончания. '
        'Когда ≤ 0.1 — выдай итог и добавь маркер окончания $stopSequence. '
        'Маркер будет скрыт от пользователя.';

    final memoryBlock = _memory == null || _memory!.trim().isEmpty
        ? ''
        : '\n\n=== ПАМЯТЬ (summary контекста) ===\n${_memory!.trim()}\n=== КОНЕЦ ПАМЯТИ ===';

    final effectiveFormat = overrideResponseFormat ?? _settings.responseFormat;
    if (effectiveFormat == ResponseFormat.json) {
      final schema = overrideJsonSchema ?? _settings.customJsonSchema ?? '{"key":"value"}';
      final endNote =
          'Finish your output with the exact token: $stopSequence. NOTE: The stop token is for the agent and will be hidden from the user.';
      return 'You are a code-focused assistant that returns data in JSON format. '
          'Think like a software engineer. Provide concise, actionable outputs. '
          'Evaluate uncertainty 0..1; if > 0.1 ask clarifying questions first and do NOT output final JSON nor stop token. '
          'Once ≤ 0.1, return ONLY minified JSON strictly matching schema: $schema $endNote$memoryBlock';
    }

    return '${_settings.systemPrompt}\n\n$codeOpsGuide\n$uncertaintyPolicy$memoryBlock';
  }

  /// Сжать историю через LLM и сохранить summary в [_memory].
  /// По умолчанию берём всё, кроме последних keepTail сообщений.
  Future<void> compressHistory({int keepTail = 6, int maxChars = 1200}) async {
    if (_history.isEmpty) return;

    // Формируем краткую сводку: факты, решения, TODO, ограничения, указания на файлы.
    final usecase = _resolveUseCase();

    final historyText = _history
        .map((m) => '[${m.role}] ${m.content}')
        .join('\n');

    final prompt =
        'Сожми историю технического диалога для работы с кодом. '
        'Выведи краткую конспективную память в виде пунктов: \n'
        '- Контекст, цели и принятые решения\n'
        '- Ключевые файлы/директории и сущности\n'
        '- Текущие TODO и ограничения\n'
        '- Форматы ответов/политики (если есть)\n'
        'Строго не более $maxChars символов. Без рассуждений и преамбулы.\n\n'
        'История:\n$historyText';

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': 'Ты умеешь кратко конспектировать диалоги разработчиков.'},
      {'role': 'user', 'content': prompt},
    ];

    final summary = await usecase.complete(messages: messages, settings: _settings);
    _memory = summary.trim();

    // Оставляем хвост истории (последние сообщения) для контекста диалога
    if (keepTail > 0 && _history.length > keepTail) {
      _history.removeRange(0, _history.length - keepTail);
    }
  }

  /// Запускает или поднимает локальный Docker-контейнер с Java JDK через MCP сервер.
  Future<Map<String, dynamic>> startLocalJavaDocker({
    String? containerName,
    String? image,
    int? port,
    String? extraArgs,
  }) async {
    final url = _settings.mcpServerUrl?.trim();
    if (!_settings.useMcpServer || url == null || url.isEmpty) {
      throw StateError('MCP сервер не настроен. Включите useMcpServer и задайте mcpServerUrl в настройках.');
    }

    final client = McpClient();
    try {
      await client.connect(url);
      // Быстрый health‑check MCP: короткий таймаут на initialize
      try {
        await client.initialize(timeout: const Duration(seconds: 3));
      } catch (e) {
        throw StateError('MCP сервер недоступен или не отвечает. Проверьте, что сервер запущен и URL "$url" корректен. Детали: $e');
      }

      final resp = await client.toolsCall('docker_start_java', {
        if (containerName != null) 'container_name': containerName,
        if (image != null) 'image': image,
        if (port != null) 'port': port,
        if (extraArgs != null) 'extra_args': extraArgs,
      }, timeout: const Duration(seconds: 30));
      // Сервер возвращает { name, result }
      if (resp is Map<String, dynamic>) {
        return (resp['result'] ?? resp) as Map<String, dynamic>;
      }
      return {'result': resp};
    } finally {
      await client.close();
    }
  }

  /// Основной метод запроса. Хранит историю, использует MCP и память (summary).
  Future<Map<String, dynamic>> ask(
    String userText, {
    bool autoCompress = true,
    ResponseFormat? overrideResponseFormat,
    String? overrideJsonSchema,
  }) async {
    if (userText.trim().isEmpty) {
      return {'answer': '', 'isFinal': false, 'mcp_used': false};
    }

    // Добавляем в историю и ограничиваем размер
    final limit = _settings.historyDepth.clamp(0, 100);
    _history.add(_Msg('user', userText));
    if (_history.length > limit) {
      _history.removeRange(0, _history.length - limit);
    }

    // При необходимости — авто-сжатие контекста
    if (autoCompress && _history.length >= limit) {
      try { await compressHistory(); } catch (_) {}
    }

    // Обогащаем контекст MCP (GitHub и т.п.)
    final enrichedContext = await _mcpIntegrationService.enrichContext(userText, _settings);
    final system = _mcpIntegrationService.buildEnrichedSystemPrompt(
      _buildSystemContent(
        overrideResponseFormat: overrideResponseFormat,
        overrideJsonSchema: overrideJsonSchema,
      ),
      enrichedContext,
    );

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': system},
      for (final m in _history) {'role': m.role, 'content': m.content},
    ];

    try {
      final usecase = _resolveUseCase();
      var answer = await usecase.complete(messages: messages, settings: _settings);

      // Определяем финальность по маркеру
      var isFinal = answer.contains(stopSequence);
      if (isFinal) {
        answer = answer.replaceAll(stopSequence, '').trim();
      }

      _history.add(_Msg('assistant', answer));
      if (_history.length > limit) {
        _history.removeRange(0, _history.length - limit);
      }

      return {
        'answer': answer,
        'isFinal': isFinal,
        'mcp_used': enrichedContext['mcp_used'] ?? false,
      };
    } catch (e) {
      return {
        'answer': 'Ошибка: $e',
        'isFinal': true,
        'mcp_used': false,
      };
    }
  }
}

class _Msg {
  final String role; // 'user' | 'assistant'
  final String content;
  _Msg(this.role, this.content);
}
