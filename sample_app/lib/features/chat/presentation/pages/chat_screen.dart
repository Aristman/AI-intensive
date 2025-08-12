import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/message_entity.dart';
import '../bloc/bloc.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';

class ChatScreen extends StatefulWidget {
  final String model;
  final String systemPrompt;
  final String? jsonSchema;

  const ChatScreen({
    Key? key,
    required this.model,
    required this.systemPrompt,
    this.jsonSchema,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  late final ChatBloc _chatBloc;

  @override
  void initState() {
    super.initState();
    _chatBloc = context.read<ChatBloc>();
    _chatBloc.add(const LoadChatHistory());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleSendMessage(String message) {
    if (message.trim().isNotEmpty) {
      _chatBloc.add(
        SendMessage(
          message: message,
          model: widget.model,
          systemPrompt: widget.systemPrompt,
          jsonSchema: widget.jsonSchema,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat - ${widget.model}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Настройки',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.assignment),
            tooltip: 'Requirements Agent',
            onPressed: () => Navigator.pushNamed(context, '/requirements-agent'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              _chatBloc.add(const ClearChatHistory());
            },
            tooltip: 'Clear chat',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: BlocConsumer<ChatBloc, ChatState>(
              listener: (context, state) {
                if (state is ChatMessageSent || state is ChatError) {
                  _scrollToBottom();
                }
              },
              builder: (context, state) {
                if (state is ChatInitial || state is ChatLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is ChatError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Error: ${state.message}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _chatBloc.add(const LoadChatHistory()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                List<MessageEntity> messages = [];

                if (state is ChatMessagesLoaded) {
                  messages = state.messages;
                } else if (state is ChatMessageSending) {
                  messages = state.messages;
                } else if (state is ChatMessageSent) {
                  messages = state.messages;
                }

                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Start a new conversation'),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return MessageBubble(
                      key: ValueKey('${message.id}_${message.timestamp}'),
                      message: message,
                      isLastMessage: index == messages.length - 1,
                    );
                  },
                );
              },
            ),
          ),
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              return ChatInput(
                controller: _textController,
                onSendMessage: _handleSendMessage,
                isLoading: state is ChatMessageSending,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a message';
                  }
                  return null;
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
