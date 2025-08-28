import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:telegram_summarizer/state/settings_state.dart';

/// Простой агент с сохранением контекста и возможностью сжатия контекста через LLM.
class SimpleAgent {
  static const String _kAgentHistoryKey = 'agentHistory';
  static const int _tokenCompressThreshold = 2000;
  final LlmUseCase _llm;
  final List<Map<String, String>> _history = [];

  /// Базовый системный промпт, который можно задать при создании агента.
  final String? systemPrompt;

  SimpleAgent(this._llm, {this.systemPrompt}) {
    if (systemPrompt != null && systemPrompt!.isNotEmpty) {
      _history.add({'role': 'system', 'content': systemPrompt!});
    }
  }

  /// Текущая копия истории в формате LLM-сообщений.
  List<Map<String, String>> get history => List.unmodifiable(_history);

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
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAgentHistoryKey, jsonEncode(_history));
  }

  Future<void> clear() async {
    _history.clear();
    await _save();
  }

  /// Добавить пользовательское сообщение в историю.
  void addUserMessage(String text) {
    if (text.trim().isEmpty) return;
    _history.add({'role': 'user', 'content': text.trim()});
  }

  /// Добавить ответ ассистента в историю.
  void addAssistantMessage(String text) {
    if (text.trim().isEmpty) return;
    _history.add({'role': 'assistant', 'content': text.trim()});
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

    final reply = await _llm.complete(
      messages: _history,
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

    addAssistantMessage(reply);
    await _save();
    return reply;
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

    _history
      ..clear()
      ..add({'role': 'system', 'content': 'Сводка диалога:\n$summary'});

    if (keepLastUser && lastUser != null && (lastUser['content'] ?? '').isNotEmpty) {
      _history.add(lastUser);
    }
    await _save();
  }

  // Грубая оценка токенов (~4 символа на токен)
  int _estimateTokens(List<Map<String, String>> messages) {
    int sum = 0;
    for (final m in messages) {
      sum += ((m['content'] ?? '').length / 4).ceil();
    }
    return sum;
  }
}
