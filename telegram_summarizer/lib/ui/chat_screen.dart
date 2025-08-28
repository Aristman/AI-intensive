import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:telegram_summarizer/core/models/message.dart';
import 'package:telegram_summarizer/state/chat_state.dart';
import 'package:telegram_summarizer/state/settings_state.dart';
import 'package:telegram_summarizer/ui/settings_screen.dart';
import 'package:telegram_summarizer/widgets/message_bubble.dart';
import 'package:telegram_summarizer/widgets/summary_card.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputController.text;
    final settings = context.read<SettingsState>();
    context.read<ChatState>().sendUserMessage(text, settings);
    _inputController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final chat = context.watch<ChatState>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Telegram Summarizer'),
            const SizedBox(width: 12),
            Chip(
              label: Text(settings.llmModel),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        actions: [
          // MCP status indicator
          if (chat.hasMcp)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Tooltip(
                message: chat.mcpConnecting
                    ? 'MCP подключается… (${settings.mcpUrl})'
                    : chat.mcpConnected
                        ? 'MCP подключен (${settings.mcpUrl})'
                        : (chat.mcpError != null
                            ? 'Ошибка MCP: ${chat.mcpError}\n(${settings.mcpUrl})'
                            : 'MCP отключен (${settings.mcpUrl})'),
                child: Icon(
                  Icons.circle,
                  size: 14,
                  color: chat.mcpConnecting
                      ? Colors.amber
                      : (chat.mcpConnected
                          ? Colors.green
                          : Colors.red),
                ),
              ),
            ),
          if (chat.hasMcp)
            IconButton(
              tooltip: 'Переподключить MCP',
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await context.read<ChatState>().reconnectMcp();
                if (!mounted) return;
                final cs = context.read<ChatState>();
                if (cs.mcpError != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Не удалось подключиться к MCP: ${cs.mcpError}'),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
              },
            ),
          IconButton(
            tooltip: 'Очистить контекст',
            icon: const Icon(Icons.delete_outline),
            onPressed: chat.messages.isEmpty ? null : () => chat.clear(),
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: chat.messages.length,
              itemBuilder: (context, index) {
                final msg = chat.messages[index];
                return Column(
                  crossAxisAlignment: msg.author == MessageAuthor.user
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    MessageBubble(message: msg),
                    if (msg.structuredContent != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: SummaryCard(content: msg.structuredContent!),
                      ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chat_input'),
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Введите запрос…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('send_button'),
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
