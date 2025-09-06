import 'dart:convert';
import 'dart:developer' as dev;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:telegram_summarizer/state/settings_state.dart';
import 'package:telegram_summarizer/data/mcp/mcp_client.dart';

/// Простой агент с сохранением контекста и возможностью сжатия контекста через LLM.
class AgentReply {
  final String text;
  final Map<String, dynamic>? structuredContent;

  AgentReply({required this.text, this.structuredContent});
}

/// Простой агент с сохранением контекста и возможностью сжатия контекста через LLM.
class SimpleAgent {
  static const String _kAgentHistoryKey = 'agentHistory';
  static const int _tokenCompressThreshold = 2000;
  final LlmUseCase _llm;
  final List<Map<String, String>> _history = [];
  McpClient? _mcp;
  Map<String, dynamic>? _mcpCapabilities;

  /// Базовый системный промпт, который можно задать при создании агента.
  final String? systemPrompt;

  SimpleAgent(this._llm, {this.systemPrompt, McpClient? mcp}) : _mcp = mcp {
    if (systemPrompt != null && systemPrompt!.isNotEmpty) {
      _history.add({'role': 'system', 'content': systemPrompt!});
      dev.log('Agent.init: add systemPrompt="${systemPrompt!}"',
          name: 'SimpleAgent', level: 800);
    }
  }

  /// Текущая копия истории в формате LLM-сообщений.
  List<Map<String, String>> get history => List.unmodifiable(_history);

  /// Текущие capabilities MCP (кэшированы после refreshMcpCapabilities).
  Map<String, dynamic>? get mcpCapabilities => _mcpCapabilities == null
      ? null
      : Map<String, dynamic>.from(_mcpCapabilities!);

  /// Очистка истории.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_kAgentHistoryKey);
    _history.clear();
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final list = jsonDecode(jsonStr);
        if (list is List) {
          _history.addAll(
              list.whereType<Map>().map((e) => Map<String, String>.from(e)));
        }
      } catch (_) {
        // ignore
      }
    }
    if (_history.isEmpty && systemPrompt != null && systemPrompt!.isNotEmpty) {
      _history.add({'role': 'system', 'content': systemPrompt!});
      await _save();
    }
    dev.log(
        'Agent.load: historyLen=${_history.length} history=${jsonEncode(_history)}',
        name: 'SimpleAgent');
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAgentHistoryKey, jsonEncode(_history));
    dev.log('Agent._save: historyLen=${_history.length}',
        name: 'SimpleAgent', level: 700);
  }

  Future<void> clear() async {
    _history.clear();
    await _save();
  }

  /// Добавить пользовательское сообщение в историю.
  void addUserMessage(String text) {
    if (text.trim().isEmpty) return;
    _history.add({'role': 'user', 'content': text.trim()});
    dev.log(
        'Agent.addUser: text="${text.trim()}" historyLen=${_history.length}',
        name: 'SimpleAgent');
  }

  /// Добавить ответ ассистента в историю.
  void addAssistantMessage(String text) {
    if (text.trim().isEmpty) return;
    _history.add({'role': 'assistant', 'content': text.trim()});
    dev.log(
        'Agent.addAssistant: text="${text.trim()}" historyLen=${_history.length}',
        name: 'SimpleAgent');
  }

  /// Спросить модель с учётом сохранённого контекста.
  /// Возвращает ответ и автоматически добавляет его в историю.
  Future<String> ask(
    String userText,
    SettingsState settings, {
    double temperature = 0.2,
    int maxTokens = 256,
    Duration timeout = const Duration(seconds: 20),
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async {
    // Авто-сжатие перед добавлением нового сообщения, если превысим порог
    final prospective = [
      ..._history,
      {'role': 'user', 'content': userText.trim()},
    ];
    if (_estimateTokens(prospective) > _tokenCompressThreshold) {
      await compressContext(settings,
          keepLastUser: true,
          maxTokens: maxTokens,
          timeout: timeout,
          retries: retries,
          retryDelay: retryDelay);
    }

    addUserMessage(userText);

    final msgs = _messagesForLlm();
    dev.log(
        'Agent.ask: sending to LLM. hasCaps=${_mcpCapabilities != null} messages=${jsonEncode(msgs)}',
        name: 'SimpleAgent');

    final reply = await _llm.complete(
      messages: msgs,
      modelUri: settings.llmModel,
      iamToken: settings.iamToken,
      apiKey: settings.apiKey,
      folderId: settings.folderId,
      temperature: temperature,
      maxTokens: maxTokens,
      timeout: timeout,
      retries: retries,
      retryDelay: retryDelay,
    );

    dev.log('Agent.ask: got reply text="$reply"', name: 'SimpleAgent');
    addAssistantMessage(reply);
    await _save();
    return reply;
  }

  /// Расширенный диалог: понимает прямые JSON-команды tool_call и умеет вызывать MCP инструмент.
  Future<AgentReply> askRich(
    String userText,
    SettingsState settings, {
    double temperature = 0.2,
    int maxTokens = 256,
    Duration timeout = const Duration(seconds: 20),
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async {
    // Авто-сжатие перед добавлением нового сообщения, если превысим порог
    final prospective = [
      ..._history,
      {'role': 'user', 'content': userText.trim()},
    ];
    if (_estimateTokens(prospective) > _tokenCompressThreshold) {
      await compressContext(settings,
          keepLastUser: true,
          maxTokens: maxTokens,
          timeout: timeout,
          retries: retries,
          retryDelay: retryDelay);
    }

    addUserMessage(userText);

    // Будущий structuredContent
    Map<String, dynamic>? structured;

    // Если MCP подключен — попробуем заранее получить structuredContent через summarize (если сервер поддерживает)
    try {
      if (_mcp != null && _mcp!.isConnected) {
        final sum = await _mcp!.summarize(userText, timeout: timeout);
        structured = sum;
        dev.log(
            'Agent.askRich: pre-fetched summarize via MCP=${jsonEncode(sum)}',
            name: 'SimpleAgent');
      }
    } catch (e) {
      dev.log('Agent.askRich: summarize prefetch failed: $e',
          name: 'SimpleAgent', level: 800);
    }

    // Попытка распознать прямой tool_call в пользовательском сообщении
    Map<String, dynamic>? userToolCall;
    final userJson =
        _extractJsonFromMarkdown(userText) ?? _tryParseRawJson(userText);
    if (userJson != null && userJson['tool_call'] is Map<String, dynamic>) {
      userToolCall = Map<String, dynamic>.from(userJson['tool_call'] as Map);
      dev.log(
          'Agent.askRich: detected DIRECT user tool_call=${jsonEncode(userToolCall)}',
          name: 'SimpleAgent');
    }

    final baseMsgs = _messagesForLlm();
    String finalReplyText;

    if (userToolCall != null && _mcp != null && _mcp!.isConnected) {
      // Выполнить инструмент и затем спросить LLM для итогового ответа
      try {
        final toolName = userToolCall['name'] as String?;
        final toolArgs = (userToolCall['arguments'] is Map)
            ? Map<String, dynamic>.from(userToolCall['arguments'] as Map)
            : null;
        if (toolName == null || toolArgs == null) {
          throw StateError(
              'Некорректный формат tool_call: name/arguments отсутствуют');
        }
        dev.log(
            'Agent.askRich: executing DIRECT tool $toolName with args=${jsonEncode(toolArgs)}',
            name: 'SimpleAgent');
        final toolResult = await _mcp!.call(
            'tools/call', {'name': toolName, 'arguments': toolArgs},
            timeout: timeout);
        dev.log('Agent.askRich: DIRECT tool result=${jsonEncode(toolResult)}',
            name: 'SimpleAgent');
        structured = toolResult;

        final followUpMsgs = [
          ...baseMsgs,
          {
            'role': 'user',
            'content':
                'Результат выполнения инструмента $toolName: ${jsonEncode(toolResult)}. Теперь дай полный ответ пользователю на основе этого результата.'
          }
        ];
        finalReplyText = await _llm.complete(
          messages: followUpMsgs,
          modelUri: settings.llmModel,
          iamToken: settings.iamToken,
          apiKey: settings.apiKey,
          folderId: settings.folderId,
          temperature: temperature,
          maxTokens: maxTokens,
          timeout: timeout,
          retries: retries,
          retryDelay: retryDelay,
        );
      } catch (e) {
        dev.log('Agent.askRich: DIRECT tool execution failed: $e',
            name: 'SimpleAgent', level: 900);
        finalReplyText =
            'Ошибка выполнения инструмента: $e. Проверьте корректность JSON и попробуйте снова.';
      }
    } else {
      // Обычный цикл: сперва спросить LLM
      dev.log(
          'Agent.askRich: sending to LLM. hasCaps=${_mcpCapabilities != null} messages=${jsonEncode(baseMsgs)}',
          name: 'SimpleAgent');
      final replyText = await _llm.complete(
        messages: baseMsgs,
        modelUri: settings.llmModel,
        iamToken: settings.iamToken,
        apiKey: settings.apiKey,
        folderId: settings.folderId,
        temperature: temperature,
        maxTokens: maxTokens,
        timeout: timeout,
        retries: retries,
        retryDelay: retryDelay,
      );
      dev.log('Agent.askRich: got reply text="$replyText"',
          name: 'SimpleAgent');

      // Попытка извлечь tool_call из ответа ассистента (markdown или сырой JSON)
      Map<String, dynamic>? toolCall;
      final extractedJson =
          _extractJsonFromMarkdown(replyText) ?? _tryParseRawJson(replyText);
      if (extractedJson != null && extractedJson['tool_call'] is Map) {
        toolCall = Map<String, dynamic>.from(extractedJson['tool_call'] as Map);
        dev.log('Agent.askRich: detected tool call=${jsonEncode(toolCall)}',
            name: 'SimpleAgent');
      }

      finalReplyText = replyText;

      if (toolCall != null && _mcp != null && _mcp!.isConnected) {
        try {
          final toolName = toolCall['name'] as String?;
          final toolArgs = (toolCall['arguments'] is Map)
              ? Map<String, dynamic>.from(toolCall['arguments'] as Map)
              : null;
          if (toolName != null && toolArgs != null) {
            dev.log(
                'Agent.askRich: executing tool $toolName with args=${jsonEncode(toolArgs)}',
                name: 'SimpleAgent');
            final toolResult = await _mcp!.call(
                'tools/call', {'name': toolName, 'arguments': toolArgs},
                timeout: timeout);
            dev.log('Agent.askRich: tool result=${jsonEncode(toolResult)}',
                name: 'SimpleAgent');
            structured = toolResult;

            final followUpMsgs = [
              ...baseMsgs,
              {'role': 'assistant', 'content': replyText},
              {
                'role': 'user',
                'content':
                    'Результат выполнения инструмента $toolName: ${jsonEncode(toolResult)}. Теперь дай полный ответ пользователю на основе этого результата.'
              }
            ];
            finalReplyText = await _llm.complete(
              messages: followUpMsgs,
              modelUri: settings.llmModel,
              iamToken: settings.iamToken,
              apiKey: settings.apiKey,
              folderId: settings.folderId,
              temperature: temperature,
              maxTokens: maxTokens,
              timeout: timeout,
              retries: retries,
              retryDelay: retryDelay,
            );
            dev.log(
                'Agent.askRich: final response after tool call="$finalReplyText"',
                name: 'SimpleAgent');
          }
        } catch (e) {
          dev.log('Agent.askRich: tool execution failed: $e',
              name: 'SimpleAgent', level: 900);
          finalReplyText =
              'Ошибка выполнения инструмента: $e. Попробуйте переформулировать запрос.';
        }
      }
    }

    addAssistantMessage(finalReplyText);
    await _save();

    return AgentReply(text: finalReplyText, structuredContent: structured);
  }

  /// Сжать текущий контекст с помощью LLM.
  /// По итогу история заменяется одной системной сводкой + (опционально) последним сообщением пользователя.
  Future<void> compressContext(
    SettingsState settings, {
    bool keepLastUser = false,
    int maxTokens = 256,
    Duration timeout = const Duration(seconds: 20),
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async {
    if (_history.isEmpty) return;

    final lastUser = keepLastUser
        ? (List<Map<String, String>>.from(_history.reversed).firstWhere(
            (m) => m['role'] == 'user',
            orElse: () => const {'role': 'user', 'content': ''}))
        : null;

    final compressionPrompt =
        'Сожми диалог выше в краткую сводку с основными фактами и решениями. '
        'Формат: краткие пункты без лишней воды.';

    // Формируем сообщения для сжатия: вся история + системная инструкция
    final messages = <Map<String, String>>[
      ..._history,
      {'role': 'system', 'content': compressionPrompt},
    ];

    dev.log(
        'Agent.compressContext: start messages=${jsonEncode(messages)} keepLastUser=$keepLastUser',
        name: 'SimpleAgent');

    final summary = await _llm.complete(
      messages: messages,
      modelUri: settings.llmModel,
      iamToken: settings.iamToken,
      apiKey: settings.apiKey,
      folderId: settings.folderId,
      temperature: 0.1,
      maxTokens: maxTokens,
      timeout: timeout,
      retries: retries,
      retryDelay: retryDelay,
    );

    dev.log('Agent.compressContext: summary="$summary"', name: 'SimpleAgent');
    _history
      ..clear()
      ..add({'role': 'system', 'content': 'Сводка диалога:\n$summary'});

    if (keepLastUser &&
        lastUser != null &&
        (lastUser['content'] ?? '').isNotEmpty) {
      _history.add(lastUser);
    }
    await _save();
    dev.log(
        'Agent.compressContext: done historyLen=${_history.length} history=${jsonEncode(_history)}',
        name: 'SimpleAgent');
  }

  // Грубая оценка токенов (~4 символа на токен)
  int _estimateTokens(List<Map<String, String>> messages) {
    int sum = 0;
    for (final m in messages) {
      sum += ((m['content'] ?? '').length / 4).ceil();
    }
    return sum;
  }

  /// Сформировать сообщения для LLM, добавив системную подсказку с возможностями MCP при наличии.
  List<Map<String, String>> _messagesForLlm() {
    final msgs = <Map<String, String>>[..._history];
    if (_mcpCapabilities != null) {
      final tools = _mcpCapabilities!['tools'];
      if (tools is List && tools.isNotEmpty) {
        msgs.add({
          'role': 'system',
          'content': 'У тебя есть доступ к внешним инструментам через MCP (Model Context Protocol).\n\n'
                  'ОСОБЕННО ВАЖНО ПОНИМАТЬ:\n'
              '- Для Telegram инструментов (tg_send_message, tg_send_photo, create_issue_and_notify):\n'
              '  * Параметр chat_id является ОПЦИОНАЛЬНЫМ\n'
              '  * Если chat_id НЕ указан, автоматически используется TELEGRAM_DEFAULT_CHAT_ID из настроек сервера\n'
              '  * НЕ проси пользователя указывать chat_id - просто используй инструмент без него!\n\n'
              'Доступные инструменты:\n${jsonEncode(tools)}\n\n'
              'Capabilities: ${jsonEncode({'tools': tools})}\n\n'
              'Когда пользователь просит отправить сообщение в Telegram, выполнить GitHub действия и т.д.,\n'
              'ты должен вернуть JSON объект в специальном формате:\n'
              '```json\n'
              '{"tool_call": {"name": "tool_name", "arguments": {...}}}\n'
              '```\n\n'
              'НЕ описывай, как использовать инструмент - делай реальный вызов!\n'
              'После получения результата инструмента ты сможешь дать пользователю осмысленный ответ.'
        });
      }
    }
    return msgs;
  }

  /// Обновить ссылку на MCP-клиент (используется при смене URL и переподключении).
  void setMcp(McpClient? mcp) {
    _mcp = mcp;
    dev.log('Agent.setMcp: ${mcp == null ? 'null' : 'updated'}',
        name: 'SimpleAgent');
  }

  /// Извлекает JSON из markdown блоков кода (```json или ```)
  Map<String, dynamic>? _extractJsonFromMarkdown(String text) {
    // Ищем блоки кода в формате ```json или просто ```
    final codeBlockRegex = RegExp(r'```(?:json)?\n(.*?)\n```', dotAll: true);
    final matches = codeBlockRegex.allMatches(text);

    for (final match in matches) {
      final jsonText = match.group(1)?.trim();
      if (jsonText != null && jsonText.isNotEmpty) {
        try {
          final parsed = jsonDecode(jsonText);
          if (parsed is Map<String, dynamic>) {
            return parsed;
          }
        } catch (e) {
          // Продолжаем искать другие блоки
          continue;
        }
      }
    }

    // Если ничего не нашли, возвращаем null
    return null;
  }

  /// Пытается распарсить строку как сырой JSON-объект (без Markdown-обёрток)
  Map<String, dynamic>? _tryParseRawJson(String text) {
    final trimmed = text.trim();
    if (!(trimmed.startsWith('{') && trimmed.endsWith('}'))) return null;
    try {
      final parsed = jsonDecode(trimmed);
      if (parsed is Map) {
        return Map<String, dynamic>.from(parsed);
      }
    } catch (_) {}
    return null;
  }

  /// Обновить сведения о возможностях MCP. Вызывать после установления соединения MCP.
  Future<void> refreshMcpCapabilities(
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (_mcp == null || !_mcp!.isConnected) return;
    try {
      dev.log('Agent.refreshMcpCapabilities: request capabilities',
          name: 'SimpleAgent');
      final caps = await _mcp!.call('capabilities', {}, timeout: timeout);
      _mcpCapabilities = caps;
      dev.log('Agent.refreshMcpCapabilities: response=${jsonEncode(caps)}',
          name: 'SimpleAgent');
    } catch (e) {
      // молча игнорируем, capabilities опциональны
      dev.log('Agent.refreshMcpCapabilities: error: $e',
          name: 'SimpleAgent', level: 900);
    }
  }
}
