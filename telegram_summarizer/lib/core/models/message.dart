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

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author.name,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        if (structuredContent != null) 'structuredContent': structuredContent,
      };

  static ChatMessage fromJson(Map<String, dynamic> json) {
    final authorStr = json['author'] as String? ?? 'user';
    final author = authorStr == 'llm' ? MessageAuthor.llm : MessageAuthor.user;
    return ChatMessage(
      id: json['id'] as String,
      author: author,
      text: json['text'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      structuredContent: json['structuredContent'] is Map<String, dynamic>
          ? json['structuredContent'] as Map<String, dynamic>
          : (json['structuredContent'] is Map
              ? Map<String, dynamic>.from(json['structuredContent'] as Map)
              : null),
    );
  }
}
