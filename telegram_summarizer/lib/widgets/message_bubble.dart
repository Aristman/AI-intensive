import 'package:flutter/material.dart';
import 'package:telegram_summarizer/core/models/message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.author == MessageAuthor.user;
    final bg = isUser ? Colors.lightBlue.shade100 : Colors.lightGreen.shade100;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: isUser ? const Radius.circular(12) : const Radius.circular(2),
      bottomRight: isUser ? const Radius.circular(2) : const Radius.circular(12),
    );

    return Align(
      alignment: align,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
        ),
        child: Text(message.text),
      ),
    );
  }
}
