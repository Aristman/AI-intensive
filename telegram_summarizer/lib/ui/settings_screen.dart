import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:telegram_summarizer/state/settings_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _modelController;
  late TextEditingController _mcpUrlController;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsState>();
    _modelController = TextEditingController(text: s.llmModel);
    _mcpUrlController = TextEditingController(text: s.mcpUrl);
  }

  @override
  void dispose() {
    _modelController.dispose();
    _mcpUrlController.dispose();
    super.dispose();
  }

  void _save() {
    final s = context.read<SettingsState>();
    s.setLlmModel(_modelController.text.trim());
    s.setMcpUrl(_mcpUrlController.text.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'LLM модель (YandexGPT)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mcpUrlController,
              decoration: const InputDecoration(
                labelText: 'MCP WebSocket URL',
                hintText: 'ws://localhost:8080',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
