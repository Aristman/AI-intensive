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
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

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
  static const String _conversationKey = 'chat_screen';
  // Audio
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isTtsLoading = false;

  bool get _useReasoning => widget.reasoningOverride == true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  bool get _isYandexReasoning =>
      _useReasoning && _appSettings.selectedNetwork == NeuralNetwork.yandexgpt;

  Future<void> _toggleRecording() async {
    if (!_isYandexReasoning) return;
    try {
      if (!_isRecording) {
        final hasPerm = await _recorder.hasPermission();
        if (!hasPerm) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нет разрешения на запись аудио')),
          );
          return;
        }
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
        await _recorder.start(
          RecordConfig(
            encoder: AudioEncoder.wav,
            bitRate: 128000,
            sampleRate: 48000, // повышаем до 48 kHz для лучшего качества
            numChannels: 1,    // моно для распознавания речи
          ),
          path: path,
        );
        setState(() => _isRecording = true);
      } else {
        final path = await _recorder.stop();
        setState(() => _isRecording = false);
        if (path == null) return;
        // Распознаем и отправляем как обычное сообщение
        setState(() => _isLoading = true);
        try {
          final recognized = await _reasoningAgent!
              .transcribeAudio(path, contentType: 'audio/wav');
          setState(() {
            _messages.add(Message(text: recognized, isUser: true));
          });
          _scrollToBottom();
          await _handleSend(recognized);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка распознавания: $e')),
          );
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Аудиозапись: $e')),
      );
    }
  }

  Future<void> _playTts(Message message) async {
    if (!_isYandexReasoning) return;
    try {
      setState(() => _isTtsLoading = true);
      final path = await _reasoningAgent!.synthesizeSpeechAudio(message.text);
      await _audioPlayer.stop();
      final lower = path.toLowerCase();
      final source = lower.endsWith('.wav')
          ? DeviceFileSource(path, mimeType: 'audio/wav')
          : lower.endsWith('.ogg')
              ? DeviceFileSource(path, mimeType: 'audio/ogg')
              : DeviceFileSource(path);
      await _audioPlayer.play(source);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка TTS: $e')),
      );
    } finally {
      if (mounted) setState(() => _isTtsLoading = false);
    }
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

    // Инициализация агента в зависимости от вкладки + загрузка истории при reasoning
    await _setupAgentsWithSettings();

    if (mounted) {
      setState(() {
        _isLoadingSettings = false;
      });
    }
  }

  // Выделено, чтобы переиспользовать для распознанного текста
  Future<void> _handleSend(String text) async {
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

  // ignore: unused_element
  Future<void> _openSettings() async {
    final result = await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          initialSettings: _appSettings,
          onSettingsChanged: (settings) async {
            var s = settings;
            if (widget.reasoningOverride != null) {
              s = s.copyWith(reasoningMode: widget.reasoningOverride);
            }
            setState(() {
              _appSettings = s;
            });
            // Переинициализация соответствующего агента с новыми настройками (+история)
            await _setupAgentsWithSettings();
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
      await _setupAgentsWithSettings();
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

  Future<void> _setupAgentsWithSettings() async {
    // Сбрасываем индикаторы MCP и загрузки
    _mcpIndicatorTimer?.cancel();
    _isUsingMcp = false;

    if (_useReasoning) {
      // Инициализируем ReasoningAgent с ключом беседы и подгружаем историю из хранилища
      _reasoningAgent = ReasoningAgent(baseSettings: _appSettings, conversationKey: _conversationKey);
      _simpleAgent = null;
      final loaded = await _reasoningAgent!.setConversationKey(_conversationKey);
      if (mounted) {
        setState(() {
          _messages
            ..clear()
            ..addAll(_mapHistoryToMessages(loaded));
        });
        // Прокрутка к низу после восстановления
        _scrollToBottom();
      }
    } else {
      // Простой агент без персистентной истории
      _simpleAgent = SimpleAgent(baseSettings: _appSettings);
      _reasoningAgent = null;
      if (mounted) {
        setState(() {
          _messages.clear();
        });
      }
    }
  }

  List<Message> _mapHistoryToMessages(List<Map<String, String>> history) {
    return [
      for (final m in history)
        Message(
          text: m['content'] ?? '',
          isUser: (m['role'] ?? 'user') == 'user',
          // Для восстановленных сообщений финальность неизвестна
          isFinal: null,
        )
    ];
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _mcpIndicatorTimer?.cancel();
    // SimpleAgent/ReasoningAgent не требуют dispose
    _audioPlayer.dispose();
    _recorder.dispose();
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
          if (_useReasoning)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton.icon(
                    key: const Key('clear_history_button'),
                    onPressed: () async {
                      if (_reasoningAgent == null) return;
                      await _reasoningAgent!.clearHistoryAndPersist();
                      if (!context.mounted) return;
                      setState(() {
                        _messages.clear();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('История очищена')),
                      );
                    },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Очистить историю'),
                  ),
                ],
              ),
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
                        if (!message.isUser && _isYandexReasoning)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (_isTtsLoading)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.volume_up, size: 20),
                                  tooltip: 'Озвучить ответ',
                                  onPressed: () => _playTts(message),
                                ),
                            ],
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
                if (_isYandexReasoning)
                  Padding(
                    padding: const EdgeInsets.only(right: 4.0),
                    child: IconButton(
                      icon: Icon(_isRecording ? Icons.stop_circle_outlined : Icons.mic),
                      color: _isRecording ? Colors.red : Theme.of(context).colorScheme.primary,
                      tooltip: _isRecording ? 'Остановить запись' : 'Записать аудио',
                      onPressed: _toggleRecording,
                    ),
                  ),
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
