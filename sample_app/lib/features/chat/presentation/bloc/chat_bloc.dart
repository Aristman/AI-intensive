import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/usecase/no_params.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/usecases/clear_chat_history_use_case.dart';
import '../../domain/usecases/get_chat_history_use_case.dart';
import '../../domain/usecases/send_message_use_case.dart';
import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final SendMessageUseCase sendMessageUseCase;
  final GetChatHistoryUseCase getChatHistoryUseCase;
  final ClearChatHistoryUseCase clearChatHistoryUseCase;

  ChatBloc({
    required this.sendMessageUseCase,
    required this.getChatHistoryUseCase,
    required this.clearChatHistoryUseCase,
  }) : super(ChatInitial()) {
    on<LoadChatHistory>(_onLoadChatHistory);
    on<SendMessage>(_onSendMessage);
    on<ClearChatHistory>(_onClearChatHistory);
    on<MessageSending>(_onMessageSending);
    on<MessageSent>(_onMessageSent);
    on<ChatErrorOccurred>(_onChatError);
  }

  Future<void> _onLoadChatHistory(
    LoadChatHistory event,
    Emitter<ChatState> emit,
  ) async {
    try {
      emit(ChatLoading());
      final result = await getChatHistoryUseCase(NoParams());
      
      result.fold(
        (failure) => emit(ChatError(failure.toString())),
        (messages) => emit(
          ChatMessagesLoaded(
            messages: messages,
            hasReachedMax: false,
          ),
        ),
      );
    } catch (e) {
      emit(ChatError('Failed to load chat history: $e'));
    }
  }

  Future<void> _onSendMessage(
    SendMessage event,
    Emitter<ChatState> emit,
  ) async {
    try {
      // Get current messages if any
      List<MessageEntity> currentMessages = [];
      if (state is ChatMessagesLoaded) {
        currentMessages = (state as ChatMessagesLoaded).messages;
      } else if (state is ChatMessageSending) {
        currentMessages = (state as ChatMessageSending).messages;
      }

      // Create user message
      final userMessage = MessageEntity(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: event.message,
        isUser: true,
        metadata: {
          'model': event.model,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      // Add user message to the list
      final updatedMessages = List<MessageEntity>.from(currentMessages)
        ..add(userMessage);

      // Emit sending state
      emit(ChatMessageSending(messages: updatedMessages));

      // Send message
      final result = await sendMessageUseCase(
        SendMessageParams(
          message: event.message,
          model: event.model,
          systemPrompt: event.systemPrompt,
          jsonSchema: event.jsonSchema,
          history: currentMessages,
        ),
      );

      // Handle result
      result.fold(
        (failure) => add(ChatErrorOccurred(failure.toString())),
        (message) => add(MessageSent(message)),
      );
    } catch (e) {
      add(ChatErrorOccurred('Failed to send message: $e'));
    }
  }

  void _onMessageSending(
    MessageSending event,
    Emitter<ChatState> emit,
  ) {
    emit(ChatMessageSending(messages: [event.message]));
  }

  void _onMessageSent(
    MessageSent event,
    Emitter<ChatState> emit,
  ) {
    if (state is ChatMessageSending) {
      final currentState = state as ChatMessageSending;
      final messages = List<MessageEntity>.from(currentState.messages)
        ..add(event.message);
      
      emit(ChatMessageSent(
        message: event.message,
        messages: messages,
      ));
      
      // Transition to loaded state after sending
      emit(ChatMessagesLoaded(messages: messages));
    }
  }

  Future<void> _onClearChatHistory(
    ClearChatHistory event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final result = await clearChatHistoryUseCase(NoParams());
      
      result.fold(
        (failure) => emit(ChatError(failure.toString())),
        (_) => emit(const ChatMessagesLoaded(messages: [])),
      );
    } catch (e) {
      emit(ChatError('Failed to clear chat history: $e'));
    }
  }

  void _onChatError(
    ChatErrorOccurred event,
    Emitter<ChatState> emit,
  ) {
    emit(ChatError(event.message));
  }
}
