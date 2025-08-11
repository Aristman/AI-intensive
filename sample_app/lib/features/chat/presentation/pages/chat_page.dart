import 'package:flutter/material.dart';
import 'package:provider/provider.dart ';
import '../../domain/models/message.dart';
import '../../domain/services/chat_service.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  bool _isLoading = false;
  late final ChatService _chatService;

  @override
  void initState() {
    super.initState();
    _chatService = ChatService();
    // Add a welcome message
    _messages.add(
      const Message(
        text: 'Hello! How can I help you today?',
        isUser: false,
        timestamp: null,
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    // Add user message
    final userMessage = Message(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _messageController.clear();
      _isLoading = true;
    });

    _scrollToBottom();

    // Get settings from provider
    final settings = context.read<SettingsProvider>();

    try {
      // Call the chat service
      final response = await _chatService.sendMessage(
        message: text,
        apiKey: settings.apiKey,
        baseUrl: settings.baseUrl,
        model: settings.selectedModel,
        systemPrompt: settings.systemPrompt,
        responseFormat: settings.responseFormat,
        jsonSchema: settings.customJsonSchema,
      );

      // Add bot response
      setState(() {
        _messages.add(
          Message(
            text: response,
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _scrollToBottom();
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.isUser 
                      ? Alignment.centerRight 
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 10.0,
                    ),
                    decoration: BoxDecoration(
                      color: message.isUser
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Column(
                      crossAxisAlignment: message.isUser 
                          ? CrossAxisAlignment.end 
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.text,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (message.timestamp != null) ...[
                          const SizedBox(height: 4.0),
                          Text(
                            '${message.timestamp!.hour}:${message.timestamp!.minute.toString().padLeft(2, '0')}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                  fontSize: 10.0,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Loading indicator
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),

          // Message input
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // Message input field
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: _isLoading ? 'Waiting for response...' : 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24.0),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceVariant,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                    ),
                    onSubmitted: _isLoading ? null : _sendMessage,
                    enabled: !_isLoading,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                  ),
                ),

                // Send button
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isLoading
                      ? null
                      : () => _sendMessage(_messageController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
