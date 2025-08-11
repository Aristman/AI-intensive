import 'package:flutter/material.dart';

class ChatMessageList extends StatelessWidget {
  final List<Message> messages;
  final ScrollController scrollController;
  final bool isLoading;
  final bool isJson;
  final String? jsonString;

  const ChatMessageList({
    Key? key,
    required this.messages,
    required this.scrollController,
    this.isLoading = false,
    this.isJson = false,
    this.jsonString,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      itemCount: messages.length + (isLoading ? 1 : 0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final message = messages[index];
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            decoration: BoxDecoration(
              color: message.isUser
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Text(
              message.text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        );
      },
    );
  }
}

class Message {
  final String text;
  final bool isUser;

  Message({required this.text, required this.isUser});
}
