import 'package:equatable/equatable.dart';
import '../../domain/entities/message_entity.dart';

abstract class ChatState extends Equatable {
  const ChatState();

  @override
  List<Object?> get props => [];
}

class ChatInitial extends ChatState {}

class ChatLoading extends ChatState {}

class ChatMessagesLoaded extends ChatState {
  final List<MessageEntity> messages;
  final bool hasReachedMax;

  const ChatMessagesLoaded({
    required this.messages,
    this.hasReachedMax = false,
  });

  @override
  List<Object?> get props => [messages, hasReachedMax];

  ChatMessagesLoaded copyWith({
    List<MessageEntity>? messages,
    bool? hasReachedMax,
  }) {
    return ChatMessagesLoaded(
      messages: messages ?? this.messages,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
    );
  }
}

class ChatMessageSending extends ChatState {
  final List<MessageEntity> messages;

  const ChatMessageSending({required this.messages});

  @override
  List<Object?> get props => [messages];
}

class ChatMessageSent extends ChatState {
  final MessageEntity message;
  final List<MessageEntity> messages;

  const ChatMessageSent({
    required this.message,
    required this.messages,
  });

  @override
  List<Object?> get props => [message, messages];
}

class ChatError extends ChatState {
  final String message;

  const ChatError(this.message);

  @override
  List<Object?> get props => [message];
}
