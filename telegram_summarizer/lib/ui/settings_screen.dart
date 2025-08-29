import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:telegram_summarizer/state/settings_state.dart';
import 'package:telegram_summarizer/state/chat_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _modelController;
  late TextEditingController _mcpUrlController;
  late TextEditingController _iamController;
  late TextEditingController _folderController;
  late TextEditingController _apiKeyController;
  late String _mcpClientType; // 'standard' | 'github_telegram'

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsState>();
    _modelController = TextEditingController(text: s.llmModel);
    _mcpUrlController = TextEditingController(text: s.mcpUrl);
    _iamController = TextEditingController(text: s.iamToken);
    _folderController = TextEditingController(text: s.folderId);
    _apiKeyController = TextEditingController(text: s.apiKey);
    _mcpClientType = s.mcpClientType;
  }

  @override
  void dispose() {
    _modelController.dispose();
    _mcpUrlController.dispose();
    _iamController.dispose();
    _folderController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.read<SettingsState>();
    final chat = context.read<ChatState>();
    final newUrl = _mcpUrlController.text.trim();

    await s.setLlmModel(_modelController.text.trim());
    await s.setMcpUrl(newUrl);
    await s.setMcpClientType(_mcpClientType);
    await s.setIamToken(_iamController.text.trim());
    await s.setFolderId(_folderController.text.trim());
    await s.setApiKey(_apiKeyController.text.trim());

    // Немедленно применяем новый MCP URL и тип клиента
    await chat.applyMcp(newUrl, _mcpClientType);

    if (mounted) Navigator.of(context).pop();
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
                labelText: 'MCP URL (ws(s):// или http(s)://)',
                hintText: 'https://tgtoolkit.azazazaza.work',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _mcpClientType,
              decoration: const InputDecoration(
                labelText: 'Тип MCP клиента',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'standard', child: Text('Стандартный')),
                DropdownMenuItem(value: 'github_telegram', child: Text('GitHub + Telegram')),
              ],
              onChanged: (v) => setState(() { _mcpClientType = v ?? 'standard'; }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _iamController,
              decoration: const InputDecoration(
                labelText: 'Yandex IAM Token',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _folderController,
              decoration: const InputDecoration(
                labelText: 'Folder ID (x-folder-id)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'Yandex API Key (fallback)',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
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
