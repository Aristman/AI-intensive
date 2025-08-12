import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sample_app/features/requirements_agent/domain/entities/agent_state.dart' as domain;
import 'package:sample_app/features/requirements_agent/presentation/bloc/agent_bloc.dart';
import 'package:sample_app/features/requirements_agent/presentation/bloc/agent_event.dart';
import 'package:sample_app/features/requirements_agent/presentation/bloc/agent_state.dart' as presentation;

class RequirementsAgentScreen extends StatefulWidget {
  const RequirementsAgentScreen({super.key});

  @override
  State<RequirementsAgentScreen> createState() => _RequirementsAgentScreenState();
}

class _RequirementsAgentScreenState extends State<RequirementsAgentScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    context.read<AgentBloc>().add(const AgentInitialize());
    _scrollToBottom();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }
  
  void _showResetConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Начать заново?'),
        content: const Text('Вы уверены, что хотите начать сбор требований заново? Текущий прогресс будет потерян.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AgentBloc>().add(const AgentReset());
            },
            child: const Text('Начать заново', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сбор требований'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Начать заново',
            onPressed: () {
              _showResetConfirmation(context);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: BlocConsumer<AgentBloc, presentation.AgentState>(
        listener: (context, state) {
          if (state is presentation.AgentError) {
            _isLoading = false;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error ?? 'Произошла ошибка'),
                backgroundColor: Colors.red,
                action: SnackBarAction(
                  label: 'Понятно',
                  textColor: Colors.white,
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  },
                ),
              ),
            );
          } else if (state is presentation.AgentQuestion) {
            _isLoading = false;
            _focusNode.requestFocus();
          } else if (state is presentation.AgentLoading) {
            _isLoading = true;
          } else if (state is presentation.AgentCompleted) {
            _isLoading = false;
          }
          _scrollToBottom();
        },
        builder: (context, state) {
          return Column(
            children: [
              Expanded(
                child: _buildMessages(state),
              ),
              if (state is presentation.AgentQuestion) _buildInput(state),
              if (state is presentation.AgentLoading) _buildLoading(),
              if (state is presentation.AgentCompleted) _buildCompletionButtons(context, state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMessageBubble(String message, {required bool isUser}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) const CircleAvatar(child: Icon(Icons.face_retouching_natural)),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isUser 
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isUser 
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser) const CircleAvatar(child: Icon(Icons.person)),
        ],
      ),
    );
  }

  Widget _buildMessages(presentation.AgentState state) {
    final agentState = state.agentState;
    if (agentState == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Add progress header
    Widget header = _buildProgressHeader(agentState);
    
    // Build conversation history from questions
    final messages = <Widget>[];
  
    // Add welcome message if no questions yet
    if (agentState.questions.isEmpty) {
      messages.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Здравствуйте! Я помогу вам составить техническое задание.\n\nОтвечайте на вопросы максимально подробно.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ),
      );
    } else {
      // Add questions as conversation history
      for (var i = 0; i < agentState.questions.length; i++) {
        messages.add(
          _buildMessageBubble(
            agentState.questions[i],
            isUser: i % 2 == 0, // Alternate between user and bot messages
          ),
        );
      }
    }
  
    Widget history = messages.isNotEmpty
        ? ListView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: messages,
          )
        : const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'Здравствуйте! Я помогу вам составить техническое задание.\n\nОтвечайте на вопросы максимально подробно.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          );

    // Current questions are now handled in the messages list  

    // Build completion section if done
    Widget? completion;
    if (state is presentation.AgentCompleted) {
      completion = _buildCompletionButtons(context, state);
    }

    return Column(
      children: [
        header,
        Expanded(child: history),
        if (completion != null) completion,
      ],
    );
  }
  
  Widget _buildProgressHeader(domain.AgentState agentState) {
    final progress = agentState.progress;
    final total = progress.values.length;
    final completed = progress.values.where((c) => c > 0.9).length;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: total > 0 ? completed / total : 0,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$completed из $total',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Собрано $completed из $total разделов',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildInput(presentation.AgentQuestion state) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Введите ответ...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  hintStyle: TextStyle(
                    color: Theme.of(context).hintColor,
                  ),
                ),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              child: FloatingActionButton.small(
                onPressed: _controller.text.trim().isEmpty ? null : _sendMessage,
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Text(
            'Обработка...',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;
    
    final message = _controller.text;
    _controller.clear();
    
    context.read<AgentBloc>().add(AgentProcessInput(message));
  }

  Widget _buildCompletionButtons(BuildContext context, presentation.AgentCompleted state) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
            'Диалог завершён!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Начать заново'),
                onPressed: () => _showResetConfirmation(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Скачать ТЗ'),
                onPressed: () {
                  // TODO: Implement download functionality
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Функциональность скачивания будет добавлена позже')),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
