import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_summarizer/core/models/message.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:telegram_summarizer/state/settings_state.dart';
import 'package:telegram_summarizer/data/mcp/mcp_client.dart';
import 'package:uuid/uuid.dart';

class ChatState extends ChangeNotifier {
  static const _kHistoryKey = 'chatHistory';
  static const int _maxHistory = 200;

  final _uuid = const Uuid();
  final List<ChatMessage> _messages = [];
  final LlmUseCase _llm;
  final McpClient? _mcp; // optional MCP client

  ChatState(this._llm, [this._mcp]);

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_kHistoryKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final list = jsonDecode(jsonStr);
        if (list is List) {
          _messages
            ..clear()
            ..addAll(list.whereType<Map>().map((e) =>
                ChatMessage.fromJson(Map<String, dynamic>.from(e as Map))));
        }
      } catch (_) {
        // ignore malformed state
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    // Truncate history if needed
    if (_messages.length > _maxHistory) {
      _messages.removeRange(0, _messages.length - _maxHistory);
    }
    final prefs = await SharedPreferences.getInstance();
    final list = _messages.map((m) => m.toJson()).toList(growable: false);
    await prefs.setString(_kHistoryKey, jsonEncode(list));
  }

  Future<void> sendUserMessage(String text, SettingsState settings) async {
    if (text.trim().isEmpty) return;
    final now = DateTime.now();
    _messages.add(ChatMessage(
      id: _uuid.v4(),
      author: MessageAuthor.user,
      text: text.trim(),
      timestamp: now,
    ));
    await _persist();
    notifyListeners();

    try {
      final responseText = await _llm.complete(
        messages: [
          for (final m in _messages)
            {
              'role': m.author == MessageAuthor.user ? 'user' : 'assistant',
              'content': m.text,
            }
        ],
        modelUri: settings.llmModel,
        iamToken: settings.iamToken,
        apiKey: settings.apiKey,
        folderId: settings.folderId,
      );

      // Create initial LLM message
      var llmMsg = ChatMessage(
        id: _uuid.v4(),
        author: MessageAuthor.llm,
        text: responseText,
        timestamp: DateTime.now(),
      );
      _messages.add(llmMsg);
      await _persist();
      notifyListeners();

      // Optionally call MCP to get structured content and attach to last LLM message
      if (_mcp != null) {
        try {
          if (!_mcp!.isConnected) {
            await _mcp!.connect();
          }
          final summary = await _mcp!.summarize(responseText);
          // Replace last message with structuredContent attached
          final last = _messages.isNotEmpty ? _messages.last : null;
          if (last != null && last.id == llmMsg.id) {
            llmMsg = ChatMessage(
              id: last.id,
              author: last.author,
              text: last.text,
              timestamp: last.timestamp,
              structuredContent: summary,
            );
            _messages[_messages.length - 1] = llmMsg;
            await _persist();
            notifyListeners();
          }
        } catch (e) {
          // Attach error as structured content for visibility
          final last = _messages.isNotEmpty ? _messages.last : null;
          if (last != null && last.id == llmMsg.id) {
            llmMsg = ChatMessage(
              id: last.id,
              author: last.author,
              text: last.text,
              timestamp: last.timestamp,
              structuredContent: {'error': e.toString()},
            );
            _messages[_messages.length - 1] = llmMsg;
            await _persist();
            notifyListeners();
          }
        }
      }
    } catch (e) {
      _messages.add(ChatMessage(
        id: _uuid.v4(),
        author: MessageAuthor.llm,
        text: 'Ошибка LLM: $e',
        timestamp: DateTime.now(),
      ));
      await _persist();
      notifyListeners();
    }
  }

  void clear() {
    _messages.clear();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kHistoryKey, '[]'));
    notifyListeners();
  }
}
