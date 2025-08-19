import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:sample_app/agents/code_ops_agent.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/models/message.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/screens/settings_screen.dart';

class CodeOpsScreen extends StatefulWidget {
  const CodeOpsScreen({super.key});

  @override
  State<CodeOpsScreen> createState() => _CodeOpsScreenState();
}

class _CodeOpsScreenState extends State<CodeOpsScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SettingsService _settingsService = SettingsService();

  late AppSettings _settings;
  bool _loadingSettings = true;
  late CodeOpsAgent _agent;

  final List<Message> _messages = [];
  bool _isLoading = false;
  bool _isUsingMcp = false;
  Timer? _mcpIndicatorTimer;

  // Pending code to execute
  String? _pendingCode;
  String? _pendingLanguage;
  String? _pendingFilename;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _openSettings() async {
    await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          initialSettings: _settings,
          onSettingsChanged: (settings) {
            if (!mounted) return;
            setState(() {
              _settings = settings;
              // Агент всегда в reasoning режиме
              _agent.updateSettings(_settings.copyWith(reasoningMode: true));
            });
          },
        ),
      ),
    );
  }

  Future<void> _loadSettings() async {
    setState(() => _loadingSettings = true);
    _settings = await _settingsService.getSettings();
    // CodeOpsAgent всегда в reasoning режиме
    _agent = CodeOpsAgent(baseSettings: _settings.copyWith(reasoningMode: true));
    if (mounted) setState(() => _loadingSettings = false);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _mcpIndicatorTimer?.cancel();
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

  bool _looksLikeCode(String text) {
    final t = text.trim();
    if (t.contains('```')) return true;
    if (t.split('\n').length > 3 && (t.contains(';') || t.contains('{') || t.contains('class '))) return true;
    return false;
  }

  Future<Map<String, dynamic>> _classifyIntent(String userText) async {
    const schema = '{"intent":"code_generate|other","language":"string?","filename":"string?","reason":"string"}';
    final res = await _agent.ask(
      'Классифицируй следующий запрос пользователя как code_generate или other. Ответи строго по схеме. Запрос: "${userText.replaceAll('"', '\\"')}"',
      overrideResponseFormat: ResponseFormat.json,
      overrideJsonSchema: schema,
    );
    final answer = res['answer'] as String? ?? '';
    try {
      final jsonMap = jsonDecode(answer) as Map<String, dynamic>;
      return jsonMap;
    } catch (_) {
      return {'intent': 'other', 'reason': 'failed_to_parse'};
    }
  }

  Future<Map<String, dynamic>?> _requestCodeJson(String userText) async {
    const codeSchema = '{"title":"string","description":"string","language":"string","filename":"string","entrypoint":"string?","code":"string"}';
    final res = await _agent.ask(
      'Сгенерируй код по запросу пользователя. Верни строго JSON по схеме. Запрос: "${userText.replaceAll('"', '\\"')}"',
      overrideResponseFormat: ResponseFormat.json,
      overrideJsonSchema: codeSchema,
    );
    final answer = res['answer'] as String? ?? '';
    try {
      final jsonMap = jsonDecode(answer) as Map<String, dynamic>;
      return jsonMap;
    } catch (_) {
      return null;
    }
  }

  void _appendMessage(Message m) {
    setState(() => _messages.add(m));
    _scrollToBottom();
  }

  Future<void> _handleRunPendingCode() async {
    if (_pendingCode == null) return;
    setState(() => _isLoading = true);
    try {
      final result = await _agent.startLocalJavaDocker();
      _appendMessage(Message(text: 'Docker/Java запущен: ${jsonEncode(result)}', isUser: false));
    } catch (e) {
      _appendMessage(Message(text: 'Ошибка запуска Docker: $e', isUser: false));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage(String text) async {
    final userText = text.trim();
    if (userText.isEmpty || _isLoading) return;

    _mcpIndicatorTimer?.cancel();

    _appendMessage(Message(text: userText, isUser: true));
    _textController.clear();
    setState(() {
      _isLoading = true;
      _isUsingMcp = false;
    });

    try {
      // If awaiting run confirmation
      if (_pendingCode != null && (userText.toLowerCase() == 'да' || userText.toLowerCase() == 'yes')) {
        await _handleRunPendingCode();
        _pendingCode = null;
        _pendingLanguage = null;
        _pendingFilename = null;
        setState(() => _isLoading = false);
        return;
      }
      if (_pendingCode != null && (userText.toLowerCase() == 'нет' || userText.toLowerCase() == 'no')) {
        _appendMessage(Message(text: 'Ок, выполнение кода отменено.', isUser: false));
        _pendingCode = null;
        _pendingLanguage = null;
        _pendingFilename = null;
        setState(() => _isLoading = false);
        return;
      }

      // If user pasted code directly
      if (_looksLikeCode(userText)) {
        _pendingCode = userText;
        _pendingLanguage = null;
        _pendingFilename = null;
        _appendMessage(Message(text: 'Обнаружен код. Запустить этот код локально? (Да/Нет)', isUser: false));
        setState(() => _isLoading = false);
        return;
      }

      // Classify intent
      final intent = await _classifyIntent(userText);
      if ((intent['intent'] as String?) == 'code_generate') {
        final codeJson = await _requestCodeJson(userText);
        if (codeJson != null) {
          final title = codeJson['title']?.toString() ?? 'Код';
          final language = codeJson['language']?.toString();
          final filename = codeJson['filename']?.toString();
          final code = codeJson['code']?.toString() ?? '';

          _pendingCode = code;
          _pendingLanguage = language;
          _pendingFilename = filename;

          // Show summary + code
          _appendMessage(Message(text: '$title\n\nФайл: ${filename ?? '-'}\nЯзык: ${language ?? '-'}', isUser: false));
          _appendMessage(Message(text: '```\n$code\n```', isUser: false));

          _appendMessage(Message(text: 'Запустить этот код локально? (Да/Нет)', isUser: false));
          setState(() => _isLoading = false);
          return;
        }
      }

      // General conversation with CodeOpsAgent
      final res = await _agent.ask(userText);
      final answer = res['answer'] as String? ?? '';
      final used = res['mcp_used'] == true;

      setState(() {
        _isUsingMcp = used;
        _isLoading = false;
      });
      _appendMessage(Message(text: answer, isUser: false));

      if (used) {
        _mcpIndicatorTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _isUsingMcp = false);
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isUsingMcp = false;
      });
      _appendMessage(Message(text: 'Ошибка: $e', isUser: false));
    }
  }

  bool _isJson(String text) {
    try {
      jsonDecode(text);
      return true;
    } catch (_) {
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
        ],
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSettings) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('CodeOps'),
            if (_isUsingMcp) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.integration_instructions,
                      size: 14,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'MCP',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Настройки',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              _agent.clearHistory();
              setState(() {
                _messages.clear();
                _pendingCode = null;
                _pendingLanguage = null;
                _pendingFilename = null;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Контекст очищен')),
              );
            },
            tooltip: 'Очистить контекст',
          ),
        ],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
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
                final isJson = !message.isUser && _isJson(message.text);
                return Align(
                  alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                    decoration: BoxDecoration(
                      color: message.isUser
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isJson) _buildJsonView(message.text),
                        if (isJson)
                          const SizedBox(height: 8),
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
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Введите сообщение...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) => _sendMessage(v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _sendMessage(_textController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
