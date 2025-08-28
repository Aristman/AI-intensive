import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegram_summarizer/core/models/message.dart';
import 'package:telegram_summarizer/domain/llm_usecase.dart';
import 'package:telegram_summarizer/state/settings_state.dart';
import 'package:telegram_summarizer/data/mcp/mcp_client.dart';
import 'package:telegram_summarizer/agents/simple_agent.dart';
import 'package:uuid/uuid.dart';

class ChatState extends ChangeNotifier {
  static const _kHistoryKey = 'chatHistory';
  static const int _maxHistory = 200;
  static const Duration _minConnectIndicator = Duration(milliseconds: 250);

  final _uuid = const Uuid();
  final List<ChatMessage> _messages = [];
  final LlmUseCase _llm;
  final McpClient? _mcp; // optional MCP client
  final SimpleAgent _agent;
  bool _mcpConnecting = false;
  String? _mcpError;

  ChatState(this._llm, [this._mcp]) : _agent = SimpleAgent(_llm, mcp: _mcp) {
    // Subscribe to MCP low-level state to update UI immediately on disconnect/error
    _mcp?.onStateChanged = () {
      // При установлении соединения обновим capabilities в агенте
      if (_mcp!.isConnected) {
        _agent.refreshMcpCapabilities();
      }
      notifyListeners();
    };
    _mcp?.onErrorCallback = (e) {
      _mcpError = e.toString();
      notifyListeners();
    };
  }

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  // MCP status helpers
  bool get hasMcp => _mcp != null;
  bool get mcpConnected => _mcp?.isConnected ?? false;
  bool get mcpConnecting => _mcpConnecting;
  String? get mcpError => _mcpError;

  Future<void> connectMcp() async {
    if (_mcp == null) return;
    _mcpError = null;
    _mcpConnecting = true;
    notifyListeners();
    try {
      final started = DateTime.now();
      await _mcp!.connect();
      // после успешного соединения запросим capabilities
      await _agent.refreshMcpCapabilities();
      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minConnectIndicator) {
        await Future.delayed(_minConnectIndicator - elapsed);
      }
    } catch (e) {
      _mcpError = e.toString();
    } finally {
      _mcpConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnectMcp() async {
    if (_mcp == null) return;
    await _mcp!.disconnect();
    notifyListeners();
  }

  Future<void> reconnectMcp() async {
    if (_mcp == null) return;
    _mcpError = null;
    _mcpConnecting = true;
    notifyListeners();
    await _mcp!.disconnect();
    try {
      final started = DateTime.now();
      await _mcp!.connect();
      // после успешного соединения запросим capabilities
      await _agent.refreshMcpCapabilities();
      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minConnectIndicator) {
        await Future.delayed(_minConnectIndicator - elapsed);
      }
    } catch (e) {
      _mcpError = e.toString();
    } finally {
      _mcpConnecting = false;
      notifyListeners();
    }
  }

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
    // Загрузим историю агента (внутренний контекст)
    await _agent.load();
    // Проверим/установим состояние MCP при старте
    if (_mcp != null) {
      await connectMcp();
      // capabilities подтянутся внутри connectMcp
    } else {
      notifyListeners();
    }
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
      // Ответ получаем через агента; агент сам учитывает capabilities MCP и может вернуть structuredContent
      final rich = await _agent.askRich(text, settings);

      final llmMsg = ChatMessage(
        id: _uuid.v4(),
        author: MessageAuthor.llm,
        text: rich.text,
        timestamp: DateTime.now(),
        structuredContent: rich.structuredContent,
      );
      _messages.add(llmMsg);
      await _persist();
      notifyListeners();
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
    // Очистим и внутренний контекст агента
    _agent.clear();
    notifyListeners();
  }
}
