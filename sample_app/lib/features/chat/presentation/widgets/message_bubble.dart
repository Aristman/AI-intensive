import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../domain/entities/message_entity.dart';

class MessageBubble extends StatelessWidget {
  final MessageEntity message;
  final bool isLastMessage;

  const MessageBubble({
    Key? key,
    required this.message,
    this.isLastMessage = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Column(
        crossAxisAlignment: message.isUser 
            ? CrossAxisAlignment.end 
            : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: message.isUser
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8.0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkdownBody(
                  data: message.content,
                  styleSheet: MarkdownStyleSheet(
                    p: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                    code: TextStyle(
                      backgroundColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[800]
                          : Colors.grey[200],
                      fontFamily: 'monospace',
                      fontSize: 14.0,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[800]
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                  ),
                ),
                if (message.metadata?['json_schema'] != null) ..._buildJsonPreview(context),
              ],
            ),
          ),
          if (isLastMessage) ..._buildMessageInfo(),
        ],
      ),
    );
  }

  List<Widget> _buildJsonPreview(BuildContext context) {
    try {
      final jsonData = message.metadata?['json_schema'];
      if (jsonData == null) return [];
      
      final prettyJson = _formatJson(jsonData);
      
      return [
        const SizedBox(height: 12.0),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.blueGrey[900]!.withValues(alpha: 0.5)
                : Colors.blue[50],
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.code,
                    size: 16.0,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4.0),
                  Text(
                    'JSON Preview',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),
              SelectableText(
                prettyJson,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.0),
              ),
            ],
          ),
        ),
      ];
    } catch (e) {
      return [];
    }
  }

  String _formatJson(dynamic jsonData) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(jsonData);
  }

  List<Widget> _buildMessageInfo() {
    final timestamp = message.metadata?['timestamp'] != null
        ? DateTime.parse(message.metadata!['timestamp']! as String)
        : null;

    return [
      const SizedBox(height: 4.0),
      Text(
        timestamp?.toLocal().toString().split('.')[0] ?? '',
        style: TextStyle(
          fontSize: 10.0,
          color: Colors.grey[500],
        ),
      ),
    ];
  }
}
