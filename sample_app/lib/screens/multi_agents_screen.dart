import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sample_app/agents/reasoning_agent.dart';
import 'package:sample_app/agents/simple_agent.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/screens/settings_screen.dart';
import 'package:sample_app/services/settings_service.dart';

class _Msg {
  final String text;
  final bool isUser;
  final bool? isFinal; // только для агента A (reasoning)
  _Msg(this.text, this.isUser, {this.isFinal});
}

class MultiAgentsScreen extends StatefulWidget {
  const MultiAgentsScreen({super.key});

  @override
  State<MultiAgentsScreen> createState() => _MultiAgentsScreenState();
}

class _MultiAgentsScreenState extends State<MultiAgentsScreen> {
  final _textController = TextEditingController();
  final _inputFocus = FocusNode();
  final _scrollA = ScrollController();
  final _scrollB = ScrollController();

  final _msgsA = <_Msg>[];
  final _msgsB = <_Msg>[];

  final _extraPrompt = 'При наличии признака окончания темы переформулируй задачу в виде краткого, самодостаточного промпта для другой нейросети. Не добавляй пояснений.';

  final _settingsService = SettingsService();
  late AppSettings _settings;
  bool _loadingSettings = true;

  ReasoningAgent? _agentA; // рассуждающий
  SimpleAgent? _agentB; // простой

  bool _sending = false;
  int? _waitingBIndex; // индекс плейсхолдера ожидания ответа B

  void _focusInputAndScroll() {
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_inputFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollA.hasClients) {
        _scrollA.animateTo(
          _scrollA.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      if (_scrollB.hasClients) {
        _scrollB.animateTo(
          _scrollB.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearAll() {
    // Чистим сообщения и историю агента A
    _agentA?.clearHistory();
    setState(() {
      _msgsA.clear();
      _msgsB.clear();
      _waitingBIndex = null;
    });
    _focusInputAndScroll();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadingSettings = true);
    _settings = await _settingsService.getSettings();

    // Инициализируем: A — ReasoningAgent, B — SimpleAgent
    _agentA = ReasoningAgent(
      baseSettings: _settings,
      extraSystemPrompt: _extraPrompt,
    );
    _agentB = SimpleAgent(baseSettings: _settings);

    if (mounted) setState(() => _loadingSettings = false);
  }

  // Отображаем текст как есть: ReasoningAgent уже очищает маркер окончания

  Future<void> _openSettings() async {
    final result = await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          initialSettings: _settings,
          onSettingsChanged: (s) {
            setState(() => _settings = s);
            // Переинициализируем агентов с новыми настройками
            _agentA = ReasoningAgent(
              baseSettings: _settings,
              extraSystemPrompt: _extraPrompt,
            );
            _agentB = SimpleAgent(baseSettings: _settings);
          },
        ),
      ),
    );

    if (result != null) {
      setState(() => _settings = result);
      _agentA = ReasoningAgent(
        baseSettings: _settings,
        extraSystemPrompt: _extraPrompt,
      );
      _agentB = SimpleAgent(baseSettings: _settings);
    }
  }

  void _appendA(_Msg m) {
    setState(() => _msgsA.add(m));
    if (_scrollA.hasClients) {
      _scrollA.animateTo(
        _scrollA.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    _focusInputAndScroll();
  }

  void _appendB(_Msg m) {
    setState(() => _msgsB.add(m));
    if (_scrollB.hasClients) {
      _scrollB.animateTo(
        _scrollB.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    _focusInputAndScroll();
  }

  Widget _bubble(BuildContext context, _Msg m) {
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: m.isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : (m.isFinal == null
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : (m.isFinal!
                      ? Colors.lightGreen.shade100
                      : Colors.yellow.shade100)),
          borderRadius: BorderRadius.circular(20.0),
        ),
        child: Text(
          m.text,
          style: TextStyle(
            color: m.isUser
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _chatPane({required String title, required List<_Msg> messages, required ScrollController scroll}) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(8.0),
              itemCount: messages.length,
              itemBuilder: (context, i) => _bubble(context, messages[i]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendToA(String text) async {
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    _appendA(_Msg(text, true));
    _textController.clear();
    try {
      final res = await _agentA!.ask(text);
      _appendA(_Msg(res.text, false, isFinal: res.isFinal));
      if (res.isFinal) {
        await _sendFinalToB(res.text);
      }
    } catch (e) {
      _appendA(_Msg('Ошибка A: $e', false));
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _sendFinalToB(String textFromA) async {
    try {
      // Добавляем плейсхолдер ожидания
      setState(() {
        _waitingBIndex = _msgsB.length;
        _msgsB.add(_Msg('Ожидаем ответа В...', false));
      });

      final promptForB = 'Выполни задачу: $textFromA';
      final answerB = await _agentB!.ask(promptForB);

      // Заменяем плейсхолдер реальным ответом
      setState(() {
        if (_waitingBIndex != null &&
            _waitingBIndex! >= 0 &&
            _waitingBIndex! < _msgsB.length) {
          _msgsB[_waitingBIndex!] = _Msg(answerB, false);
        } else {
          _msgsB.add(_Msg(answerB, false));
        }
        _waitingBIndex = null;
      });
      _focusInputAndScroll();
    } catch (e) {
      // Заменяем плейсхолдер ошибкой
      setState(() {
        final errMsg = _Msg('Ошибка B: $e', false);
        if (_waitingBIndex != null &&
            _waitingBIndex! >= 0 &&
            _waitingBIndex! < _msgsB.length) {
          _msgsB[_waitingBIndex!] = errMsg;
        } else {
          _msgsB.add(errMsg);
        }
        _waitingBIndex = null;
      });
      _focusInputAndScroll();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _inputFocus.dispose();
    _scrollA.dispose();
    _scrollB.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSettings) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Два агента: A (Reasoning) → B (Simple)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Очистить',
            onPressed: _clearAll,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          )
        ],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: isWide
          ? Row(
              children: [
                Expanded(child: _chatPane(title: 'Агент A (Reasoning)', messages: _msgsA, scroll: _scrollA)),
                Expanded(child: _chatPane(title: 'Агент B (Simple)', messages: _msgsB, scroll: _scrollB)),
              ],
            )
          : Column(
              children: [
                Expanded(child: _chatPane(title: 'Агент A (Reasoning)', messages: _msgsA, scroll: _scrollA)),
                Expanded(child: _chatPane(title: 'Агент B (Simple)', messages: _msgsB, scroll: _scrollB)),
              ],
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _inputFocus,
                enabled: !_sending,
                decoration: InputDecoration(
                  hintText: _sending ? 'Ожидаем ответа A...' : 'Сообщение для агента A...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24.0),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                ),
                onSubmitted: _sending ? null : _sendToA,
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            _sending
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _sendToA(_textController.text),
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ],
        ),
      ),
    );
  }
}
