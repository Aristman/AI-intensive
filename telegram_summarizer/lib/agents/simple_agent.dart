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
      dev.log('Agent.init: add systemPrompt="${systemPrompt!}"', name: 'SimpleAgent', level: 800);
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
          _history.addAll(list.whereType<Map>().map((e) => Map<String, String>.from(e as Map)));
        }
      } catch (_) {
        // ignore
      }
    }
    if (_history.isEmpty && systemPrompt != null && systemPrompt!.isNotEmpty) {
      _history.add({'role': 'system', 'content': systemPrompt!});
      await _save();
    }
    dev.log('Agent.load: historyLen=${_history.length} history=${jsonEncode(_history)}', name: 'SimpleAgent');
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAgentHistoryKey, jsonEncode(_history));
    dev.log('Agent._save: historyLen=${_history.length}', name: 'SimpleAgent', level: 700);
  }

  Future<void> clear() async {
    _history.clear();
    await _save();
  }

  /// Добавить пользовательское сообщение в историю.
  void addUserMessage(String text) {
    if (text.trim().isEmpty) return;
    _history.add({'role': 'user', 'content': text.trim()});
    dev.log('Agent.addUser: text="${text.trim()}" historyLen=${_history.length}', name: 'SimpleAgent');
  }

  /// Добавить ответ ассистента в историю.
  void addAssistantMessage(String text) {
    if (text.trim().isEmpty) return;
    _history.add({'role': 'assistant', 'content': text.trim()});
    dev.log('Agent.addAssistant: text="${text.trim()}" historyLen=${_history.length}', name: 'SimpleAgent');
  }

  /// Спросить модель с учётом сохранённого контекста.
  /// Возвращает ответ и автоматически добавляет его в историю.
  Future<String> ask(String userText, SettingsState settings, {
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
      await compressContext(settings, keepLastUser: true, maxTokens: maxTokens, timeout: timeout, retries: retries, retryDelay: retryDelay);
    }

    addUserMessage(userText);

    final msgs = _messagesForLlm();
    dev.log('Agent.ask: sending to LLM. hasCaps=${_mcpCapabilities != null} messages=${jsonEncode(msgs)}', name: 'SimpleAgent');

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

  /// Расширенный диалог: возвращает текст и structuredContent (например, сводку от MCP) при наличии.
  Future<AgentReply> askRich(String userText, SettingsState settings, {
    double temperature = 0.2,
    int maxTokens = 256,
    Duration timeout = const Duration(seconds: 20),
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async {
    // Поведение идентично ask(), но формируем сообщения с учётом возможностей MCP
    final prospective = [
      ..._history,
      {'role': 'user', 'content': userText.trim()},
    ];
    if (_estimateTokens(prospective) > _tokenCompressThreshold) {
      await compressContext(settings, keepLastUser: true, maxTokens: maxTokens, timeout: timeout, retries: retries, retryDelay: retryDelay);
    }

    addUserMessage(userText);

    final msgs = _messagesForLlm();
    dev.log('Agent.askRich: sending to LLM. hasCaps=${_mcpCapabilities != null} messages=${jsonEncode(msgs)}', name: 'SimpleAgent');

    final replyText = await _llm.complete(
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

    dev.log('Agent.askRich: got reply text="$replyText"', name: 'SimpleAgent');
    addAssistantMessage(replyText);
    await _save();

    Map<String, dynamic>? structured;
    if (_mcp != null && _mcp!.isConnected) {
      try {
        dev.log('Agent.askRich: MCP summarize start text="$replyText"', name: 'SimpleAgent');
        structured = await _mcp!.summarize(replyText, timeout: timeout);
        dev.log('Agent.askRich: MCP summarize result=${jsonEncode(structured)}', name: 'SimpleAgent');
      } catch (e) {
        // Игнорируем ошибки MCP здесь; ответственность UI — показать статус
        dev.log('Agent.askRich: MCP summarize error: $e', name: 'SimpleAgent', level: 900);
      }
    }
    return AgentReply(text: replyText, structuredContent: structured);
  }

  /// Сжать текущий контекст с помощью LLM.
  /// По итогу история заменяется одной системной сводкой + (опционально) последним сообщением пользователя.
  Future<void> compressContext(SettingsState settings, {
    bool keepLastUser = false,
    int maxTokens = 256,
    Duration timeout = const Duration(seconds: 20),
    int retries = 0,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async {
    if (_history.isEmpty) return;

    final lastUser = keepLastUser
        ? (List<Map<String, String>>.from(_history.reversed)
              .firstWhere((m) => m['role'] == 'user', orElse: () => const {'role': 'user', 'content': ''}))
        : null;

    final compressionPrompt =
        'Сожми диалог выше в краткую сводку с основными фактами и решениями. '
        'Формат: краткие пункты без лишней воды.';

    // Формируем сообщения для сжатия: вся история + системная инструкция
    final messages = <Map<String, String>>[
      ..._history,
      {'role': 'system', 'content': compressionPrompt},
    ];

    dev.log('Agent.compressContext: start messages=${jsonEncode(messages)} keepLastUser=$keepLastUser', name: 'SimpleAgent');

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

    if (keepLastUser && lastUser != null && (lastUser['content'] ?? '').isNotEmpty) {
      _history.add(lastUser);
    }
    await _save();
    dev.log('Agent.compressContext: done historyLen=${_history.length} history=${jsonEncode(_history)}', name: 'SimpleAgent');
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
      msgs.add({
        'role': 'system',
        'content': 'Доступны возможности внешнего MCP-сервера (JSON-RPC tools). '
            'Capabilities: ${jsonEncode(_mcpCapabilities)}. '
            'Если эти инструменты релевантны к задаче пользователя, предлагай использовать их результаты в ответе.'
      });
    }
    return msgs;
  }

  /// Обновить ссылку на MCP-клиент (используется при смене URL и переподключении).
  void setMcp(McpClient? mcp) {
    _mcp = mcp;
    dev.log('Agent.setMcp: ${mcp == null ? 'null' : 'updated'}', name: 'SimpleAgent');
  }

  /// Обновить сведения о возможностях MCP. Вызывать после установления соединения MCP.
  Future<void> refreshMcpCapabilities({Duration timeout = const Duration(seconds: 10)}) async {
    if (_mcp == null || !_mcp!.isConnected) return;
    try {
      dev.log('Agent.refreshMcpCapabilities: request', name: 'SimpleAgent');
      final caps = await _mcp!.call('capabilities', {}, timeout: timeout);
      _mcpCapabilities = caps;
      dev.log('Agent.refreshMcpCapabilities: response=${jsonEncode(caps)}', name: 'SimpleAgent');
    } catch (e) {
      // молча игнорируем, capabilities опциональны
      dev.log('Agent.refreshMcpCapabilities: error: $e', name: 'SimpleAgent', level: 900);
    }
  }
}
