import 'package:equatable/equatable.dart';

class Message extends Equatable {
  final String text;
  final bool isUser;
  final DateTime? timestamp;

  const Message({
    required this.text,
    required this.isUser,
    this.timestamp,
  });

  @override
  List<Object?> get props => [text, isUser, timestamp];

  Message copyWith({
    String? text,
    bool? isUser,
    DateTime? timestamp,
  }) {
    return Message(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
