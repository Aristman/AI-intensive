import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/screens/settings_screen.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

void main() async {
  await dotenv.load(fileName: "assets/.env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Чат-приложение',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  Message({required this.text, required this.isUser, DateTime? timestamp}) 
      : timestamp = timestamp ?? DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          isUser == other.isUser &&
          timestamp == other.timestamp;

  @override
  int get hashCode => text.hashCode ^ isUser.hashCode ^ timestamp.hashCode;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<Message> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  // API configuration
  final String _apiKey;
  static const String _apiUrl = 'https://api.deepseek.com/chat/completions';
  final SettingsService _settingsService = SettingsService();
  late AppSettings _appSettings;
  bool _isLoadingSettings = true;

  _ChatScreenState() : _apiKey = dotenv.env['DEEPSEEK_API_KEY'] ?? '';

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
            setState(() {
              _appSettings = settings;
            });
          },
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _appSettings = result;
      });
    }
  }

  // Функция для выполнения запроса к DeepSeek API
  Future<void> _fetchData(String query) async {
    if (_apiKey.isEmpty) {
      _addBotMessage('Ошибка: API ключ не найден. Пожалуйста, проверьте настройки.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Последовательность, по которой модель должна завершить ответ
      const String stopSequence = '<END>';
      // Инструкция по уточняющим вопросам и критерию полной информации
      const String uncertaintyPolicy =
          'Политика уточнений: Прежде чем выдавать итоговый ответ, оцени неопределённость результата по шкале от 0 до 1. '
          'Если неопределённость > 0.1 — задай пользователю 1–5 конкретных уточняющих вопросов (по важности), '
          'не выдавай финальный результат и не добавляй маркер окончания. '
          'Когда неопределённость ≤ 0.1 — сформируй итоговый результат, после чего добавь маркер окончания ' + stopSequence + '.';
      // Формируем контекст беседы: системное сообщение + последние сообщения из истории
      // Ограничим историю согласно настройке пользователя (Глубина истории)
      final int historyLimit = _appSettings.historyDepth.clamp(0, 100).toInt();
      final int startIndex = _messages.length > historyLimit
          ? _messages.length - historyLimit
          : 0;
      final recentMessages = _messages.sublist(startIndex);

      final String systemContent = _appSettings.responseFormat == ResponseFormat.json
          ? (
              'You are a helpful assistant that returns data in JSON format. '
              'Before producing the final JSON, evaluate your uncertainty in the completeness and correctness of the required data on a scale from 0 to 1. '
              'If uncertainty > 0.1, ask the user 1–5 clarifying questions (most important first) and do NOT output the final JSON yet, and do NOT append the stop token. '
              'Once uncertainty ≤ 0.1, return ONLY valid minified JSON strictly matching the following schema: '
              '${_appSettings.customJsonSchema ?? '{"key": "value"}'} '
              'Do not add explanations or any text outside JSON. Finish your output with the exact token: ' + stopSequence + '.'
            )
          : (
              _appSettings.systemPrompt + '\n\n' + uncertaintyPolicy
            );

      final List<Map<String, String>> chatMessages = [
        {
          'role': 'system',
          'content': systemContent,
        },
        // История чата
        for (final m in recentMessages)
          {
            'role': m.isUser ? 'user' : 'assistant',
            'content': m.text,
          },
      ];

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _appSettings.selectedNetwork == NeuralNetwork.deepseek
              ? 'deepseek-chat'
              : 'yandexgpt',
          'messages': chatMessages,
          // Мы не обрабатываем потоковые ответы, поэтому отключаем stream
          'stream': false,
          // Ограничение на количество токенов и последовательность остановки
          'max_tokens': 1500,
          'stop': [stopSequence],
          // Не навязываем принудительный JSON-формат на уровне API,
          // чтобы модель могла задавать уточняющие вопросы текстом.
          // Финальный JSON будет проверяться и отображаться на клиенте.
          'response_format': null,
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['choices'] != null && data['choices'].isNotEmpty) {
          final assistantMessage = data['choices'][0]['message']['content'];
          if (assistantMessage != null) {
            _addBotMessage(assistantMessage);
          } else {
            _addBotMessage('Не удалось получить ответ от ассистента');
          }
        } else {
          _addBotMessage('Не удалось обработать ответ сервера');
        }
      } else {
        _addBotMessage('Ошибка сервера: ${response.statusCode}\n${response.body}');
      }
    } catch (e) {
      _addBotMessage('Ошибка соединения: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _addBotMessage(String text) {
    if (text.trim().isEmpty) return;
    
    setState(() {
      _messages.add(Message(text: text, isUser: false));
    });
    
    // Прокручиваем к новому сообщению
    _scrollToBottom();
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
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
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

    // Добавляем сообщение пользователя
    setState(() {
      _messages.add(Message(text: text, isUser: true));
      _textController.clear();
    });

    _scrollToBottom();

    // Выполняем HTTP-запрос
    await _fetchData(text);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingSettings) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Чат'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Настройки',
          ),
        ],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Область сообщений
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
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceVariant,
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
          // Поле ввода сообщения
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                // Поле ввода
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
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
                    ),
                    onSubmitted: _isLoading ? null : _sendMessage,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                // Кнопка отправки
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
      ),
    );
  }
}
