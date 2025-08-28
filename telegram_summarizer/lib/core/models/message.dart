enum MessageAuthor { user, llm }

class ChatMessage {
  final String id;
  final MessageAuthor author;
  final String text;
  final DateTime timestamp;
  final Map<String, dynamic>? structuredContent; // for MCP outputs

  ChatMessage({
    required this.id,
    required this.author,
    required this.text,
    required this.timestamp,
    this.structuredContent,
  });
}
