import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:sample_app/agents/simple_agent.dart';
import 'package:sample_app/agents/reasoning_agent.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/models/message.dart';
import 'package:sample_app/screens/settings_screen.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/widgets/safe_send_text_field.dart';

class ChatScreen extends StatefulWidget {
  final String title;
  final bool? reasoningOverride; // если задано, принудительно включает/выключает режим рассуждений

  const ChatScreen({super.key, this.title = 'Чат', this.reasoningOverride});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<Message> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  final SettingsService _settingsService = SettingsService();
  late AppSettings _appSettings;
  bool _isLoadingSettings = true;
  SimpleAgent? _simpleAgent;
  ReasoningAgent? _reasoningAgent;
  bool _isUsingMcp = false;
  Timer? _mcpIndicatorTimer;

  bool get _useReasoning => widget.reasoningOverride == true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoadingSettings = true;
    });

    _appSettings = await _settingsService.getSettings();

    // Принудительно включаем/выключаем reasoning при необходимости
    if (widget.reasoningOverride != null) {
      _appSettings = _appSettings.copyWith(reasoningMode: widget.reasoningOverride);
    }

    // Инициализация агента в зависимости от вкладки
    if (_useReasoning) {
      _reasoningAgent = ReasoningAgent(baseSettings: _appSettings);
      _simpleAgent = null;
    } else {
      _simpleAgent = SimpleAgent(baseSettings: _appSettings);
      _reasoningAgent = null;
    }

    if (mounted) {
      setState(() {
        _isLoadingSettings = false;
      });
    }
  }

  Future<void> _openSettings() async {
    final result = await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          initialSettings: _appSettings,
          onSettingsChanged: (settings) {
            var s = settings;
            if (widget.reasoningOverride != null) {
              s = s.copyWith(reasoningMode: widget.reasoningOverride);
            }
            setState(() {
              _appSettings = s;
            });
            // Переинициализация соответствующего агента с новыми настройками
            if (_useReasoning) {
              _reasoningAgent = ReasoningAgent(baseSettings: _appSettings);
              _simpleAgent = null;
            } else {
              _simpleAgent = SimpleAgent(baseSettings: _appSettings);
              _reasoningAgent = null;
            }
          },
        ),
      ),
    );

    if (result != null) {
      var s = result;
      if (widget.reasoningOverride != null) {
        s = s.copyWith(reasoningMode: widget.reasoningOverride);
      }
      setState(() {
        _appSettings = s;
      });
      if (_useReasoning) {
        _reasoningAgent = ReasoningAgent(baseSettings: _appSettings);
        _simpleAgent = null;
      } else {
        _simpleAgent = SimpleAgent(baseSettings: _appSettings);
        _reasoningAgent = null;
      }
    }
  }

  bool _isJson(String text) {
    try {
      jsonDecode(text);
      return true;
    } catch (e) {
      return false;
    }
  }

  Widget _buildJsonView(String jsonString) {
    try {
      final jsonData = jsonDecode(jsonString);
      final prettyJson = const JsonEncoder.withIndent('  ').convert(jsonData);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 8.0),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'JSON Preview',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: jsonString));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('JSON скопирован в буфер обмена')),
                          );
                        },
                        tooltip: 'Копировать JSON',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[900]
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: SelectableText(
                      prettyJson,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Ответ:', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    // Отменяем предыдущий таймер, если он был
    _mcpIndicatorTimer?.cancel();

    setState(() {
      _messages.add(Message(text: text, isUser: true));
      _textController.clear();
      _isLoading = true;
      _isUsingMcp = false;
    });

    _scrollToBottom();

    try {
      if (_useReasoning) {
        final res = await _reasoningAgent!.ask(text);
        setState(() {
          _isLoading = false;
          _isUsingMcp = res['mcp_used'] ?? false;
          final result = res['result'] as ReasoningResult;
          _messages.add(Message(text: result.text, isUser: false, isFinal: result.isFinal));
        });
      } else {
        final answer = await _simpleAgent!.ask(text);
        setState(() {
          _isLoading = false;
          _isUsingMcp = answer['mcp_used'] ?? false;
          _messages.add(Message(text: answer['answer'] as String, isUser: false));
        });
      }
      
      // Если MCP был использован, устанавливаем таймер для скрытия индикатора
      if (_isUsingMcp) {
        _mcpIndicatorTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _isUsingMcp = false;
            });
          }
        });
      }
      
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isUsingMcp = false;
        _messages.add(Message(text: 'Ошибка: $e', isUser: false));
      });
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
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _mcpIndicatorTimer?.cancel();
    // SimpleAgent/ReasoningAgent не требуют dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingSettings) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
        children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 10.0,
                    ),
                    decoration: BoxDecoration(
                      color: message.isUser
                          ? Theme.of(context).colorScheme.primaryContainer
                          : (_useReasoning && message.isFinal != null
                              ? (message.isFinal!
                                  ? Colors.lightGreen.shade100
                                  : Colors.yellow.shade100)
                              : Theme.of(context).colorScheme.surfaceContainerHighest),
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!message.isUser &&
                            _appSettings.responseFormat == ResponseFormat.json &&
                            _isJson(message.text))
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildJsonView(message.text),
                              const SizedBox(height: 8),
                              Text(
                                message.text,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            message.text,
                            style: TextStyle(
                              color: message.isUser
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: SafeSendTextField(
                    controller: _textController,
                    enabled: !_isLoading,
                    hintText: _isLoading ? 'Ожидаем ответа...' : 'Введите сообщение...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24.0),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    onSend: _sendMessage,
                  ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _sendMessage(_textController.text),
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
        ],
      );
  }
}
