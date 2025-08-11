import 'package:equatable/equatable.dart';
import '../../domain/entities/message_entity.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class LoadChatHistory extends ChatEvent {
  const LoadChatHistory();
}

class SendMessage extends ChatEvent {
  final String message;
  final String model;
  final String systemPrompt;
  final String? jsonSchema;

  const SendMessage({
    required this.message,
    required this.model,
    required this.systemPrompt,
    this.jsonSchema,
  });

  @override
  List<Object?> get props => [message, model, systemPrompt, jsonSchema];
}

class ClearChatHistory extends ChatEvent {
  const ClearChatHistory();
}

class MessageSent extends ChatEvent {
  final MessageEntity message;

  const MessageSent(this.message);

  @override
  List<Object?> get props => [message];
}

class MessageSending extends ChatEvent {
  final MessageEntity message;

  const MessageSending(this.message);

  @override
  List<Object?> get props => [message];
}

class ChatErrorOccurred extends ChatEvent {
  final String message;

  const ChatErrorOccurred(this.message);

  @override
  List<Object?> get props => [message];
}
