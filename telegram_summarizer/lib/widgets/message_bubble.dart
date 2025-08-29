import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
        child: Markdown(
          data: message.text,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(fontSize: 16),
            h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            h2: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            h3: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            h4: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            h5: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            h6: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            code: const TextStyle(
              fontFamily: 'monospace',
              backgroundColor: Color(0xFFE8E8E8),
              fontSize: 14,
            ),
            codeblockDecoration: BoxDecoration(
              color: const Color(0xFFE8E8E8),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}
