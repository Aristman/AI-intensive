class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool? isFinal; // признак финального ответа (используется на reasoning-вкладке)

  Message({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.isFinal,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          isUser == other.isUser &&
          timestamp == other.timestamp &&
          isFinal == other.isFinal;

  @override
  int get hashCode => text.hashCode ^ isUser.hashCode ^ timestamp.hashCode ^ (isFinal?.hashCode ?? 0);
}
