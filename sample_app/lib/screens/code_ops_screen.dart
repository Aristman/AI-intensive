import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:sample_app/agents/code_ops_agent.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/models/message.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/screens/settings_screen.dart';
import 'package:sample_app/widgets/safe_send_text_field.dart';

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
  String? _pendingEntrypoint;

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
      // Очистить Markdown-кодблоки, если есть
      String _stripCodeFences(String text) {
        final t = text.trim();
        if (!t.contains('```')) return t;
        final start = t.indexOf('```');
        if (start == -1) return t;
        final end = t.indexOf('```', start + 3);
        if (end == -1) return t;
        var inner = t.substring(start + 3, end);
        // Удалить метку языка в первой строке, если есть
        final firstNl = inner.indexOf('\n');
        if (firstNl > -1) {
          final firstLine = inner.substring(0, firstNl).trim();
          if (firstLine.isNotEmpty && firstLine.length < 20) {
            // предполагаем, что это метка языка (java, kotlin и т.п.)
            inner = inner.substring(firstNl + 1);
          }
        }
        return inner.trim();
      }

      final cleanedCode = _stripCodeFences(_pendingCode!);
      final filename = _pendingFilename?.trim().isNotEmpty == true ? _pendingFilename!.trim() : 'Main.java';

      // Выполняем код через MCP docker_exec_java
      _isUsingMcp = true;
      final result = await _agent.execJavaInDocker(
        code: cleanedCode,
        filename: filename,
        entrypoint: _pendingEntrypoint,
        timeoutMs: 15000,
      );

      // Короткая сводка
      final compile = result['compile'] as Map<String, dynamic>?;
      final run = result['run'] as Map<String, dynamic>?;
      final success = result['success'] == true;
      final compileExit = compile?['exitCode'];
      final runExit = run?['exitCode'];

      final buf = StringBuffer();
      buf.writeln('Результат выполнения Docker/Java (success=$success):');
      if (compile != null) {
        buf.writeln('- Compile exitCode: $compileExit');
        final cErr = (compile['stderr'] as String? ?? '').trim();
        if (cErr.isNotEmpty) {
          buf.writeln('- Compile stderr (фрагмент):');
          buf.writeln(cErr.length > 300 ? cErr.substring(0, 300) + '...'
                                        : cErr);
        }
      }
      if (run != null) {
        buf.writeln('- Run exitCode: $runExit');
        final rOut = (run['stdout'] as String? ?? '').trim();
        if (rOut.isNotEmpty) {
          buf.writeln('- Run stdout (фрагмент):');
          buf.writeln(rOut.length > 300 ? rOut.substring(0, 300) + '...'
                                       : rOut);
        }
        final rErr = (run['stderr'] as String? ?? '').trim();
        if (rErr.isNotEmpty) {
          buf.writeln('- Run stderr (фрагмент):');
          buf.writeln(rErr.length > 300 ? rErr.substring(0, 300) + '...'
                                       : rErr);
        }
      }
      _appendMessage(Message(text: buf.toString(), isUser: false));
      // Убрано: не показываем сырой JSON-ответ, чтобы не засорять интерфейс
    } catch (e) {
      _appendMessage(Message(text: 'Ошибка выполнения кода в Docker: $e', isUser: false));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Погасить MCP-индикатор через 5 сек
        _mcpIndicatorTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _isUsingMcp = false);
        });
      }
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
        _pendingEntrypoint = null;
        setState(() => _isLoading = false);
        return;
      }
      if (_pendingCode != null && (userText.toLowerCase() == 'нет' || userText.toLowerCase() == 'no')) {
        _appendMessage(Message(text: 'Ок, выполнение кода отменено.', isUser: false));
        _pendingCode = null;
        _pendingLanguage = null;
        _pendingFilename = null;
        _pendingEntrypoint = null;
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
          final entrypoint = codeJson['entrypoint']?.toString();

          _pendingCode = code;
          _pendingLanguage = language;
          _pendingFilename = filename;
          _pendingEntrypoint = entrypoint;

          // Show summary + code
          _appendMessage(Message(text: '$title\n\nФайл: ${filename ?? '-'}\nЯзык: ${language ?? '-'}\nEntrypoint: ${entrypoint ?? '-'}', isUser: false));
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
                  child: SafeSendTextField(
                    controller: _textController,
                    hintText: 'Введите сообщение...',
                    border: const OutlineInputBorder(),
                    filled: false,
                    onSend: (v) => _sendMessage(v),
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
