import 'package:flutter/foundation.dart';
import 'package:telegram_summarizer/core/models/message.dart';
import 'package:uuid/uuid.dart';

class ChatState extends ChangeNotifier {
  final _uuid = const Uuid();
  final List<ChatMessage> _messages = [];

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  void sendUserMessage(String text) {
    if (text.trim().isEmpty) return;
    final now = DateTime.now();
    _messages.add(ChatMessage(
      id: _uuid.v4(),
      author: MessageAuthor.user,
      text: text.trim(),
      timestamp: now,
    ));
    // Placeholder LLM reply (MVP stub)
    _messages.add(ChatMessage(
      id: _uuid.v4(),
      author: MessageAuthor.llm,
      text: 'Ответ будет позже…',
      timestamp: now.add(const Duration(milliseconds: 1)),
    ));
    notifyListeners();
  }

  void clear() {
    _messages.clear();
    notifyListeners();
  }
}
