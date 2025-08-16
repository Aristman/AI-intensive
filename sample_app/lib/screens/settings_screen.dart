import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/services/github_mcp_service.dart';

class SettingsScreen extends StatefulWidget {
  static const Key settingsScreenKey = Key('settings_screen');
  final AppSettings initialSettings;
  final Function(AppSettings) onSettingsChanged;

  const SettingsScreen({
    super.key,
    required this.initialSettings,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _currentSettings;
  final _settingsService = SettingsService();
  final _githubMcpService = GithubMcpService();
  final _jsonSchemaController = TextEditingController();
  final _systemPromptController = TextEditingController();
  bool _isGithubTokenValid = false;
  bool _isValidatingToken = false;
  // Controllers for quick GitHub Issue creation
  final _repoOwnerController = TextEditingController();
  final _repoNameController = TextEditingController();
  final _issueTitleController = TextEditingController();
  final _issueBodyController = TextEditingController();
  bool _isCreatingIssue = false;

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.initialSettings;
    _jsonSchemaController.text = _currentSettings.customJsonSchema ?? '';
    _systemPromptController.text = _currentSettings.systemPrompt;
    _checkGithubTokenValidity();
  }

  Future<void> _checkGithubTokenValidity() async {
    // Проверяем наличие токена в .env файле
    final isValid = await _githubMcpService.validateTokenFromEnv();
    
    if (mounted) {
      setState(() {
        _isGithubTokenValid = isValid;
      });
    }
  }

  Future<void> _validateGithubToken(String token) async {
    // Этот метод больше не нужен, так как токен берется из .env
    // Оставляем для совместимости, но перенаправляем на проверку токена из .env
    await _checkGithubTokenValidity();
    
    if (mounted && !_isGithubTokenValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GitHub токен не найден в .env файле или недействителен'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleCreateIssue() async {
    if (!_isGithubTokenValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала добавьте валидный GITHUB_MCP_TOKEN в .env'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final owner = _repoOwnerController.text.trim();
    final repo = _repoNameController.text.trim();
    final title = _issueTitleController.text.trim();
    final body = _issueBodyController.text.trim();

    if (owner.isEmpty || repo.isEmpty || title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Укажите владельца, репозиторий и заголовок issue'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isCreatingIssue = true);
    try {
      final result = await _githubMcpService.createIssueFromEnv(owner, repo, title, body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Issue создан: #${result['number']}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при создании issue: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreatingIssue = false);
    }
  }

  @override
  void dispose() {
    _jsonSchemaController.dispose();
    _systemPromptController.dispose();
    _repoOwnerController.dispose();
    _repoNameController.dispose();
    _issueTitleController.dispose();
    _issueBodyController.dispose();
    super.dispose();
  }

  bool _isValidJson(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return true;
    try {
      jsonDecode(jsonString);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _saveSettings() async {
    // Validate JSON if JSON format is selected
    if (_currentSettings.responseFormat == ResponseFormat.json && 
        !_isValidJson(_currentSettings.customJsonSchema)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка: Неверный формат JSON схемы'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final success = await _settingsService.saveSettings(_currentSettings);
    if (mounted && success) {
      widget.onSettingsChanged(_currentSettings);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } else if (mounted) {
      // Показываем сообщение об ошибке, если не удалось сохранить
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить настройки')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: SettingsScreen.settingsScreenKey,
      appBar: AppBar(
        title: const Text('Настройки'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // System Prompt
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'System prompt',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('system_prompt_field'),
                      controller: _systemPromptController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Введите system prompt...',
                      ),
                      onChanged: (value) {
                        _currentSettings = _currentSettings.copyWith(
                          systemPrompt: value,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Reasoning mode
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: CheckboxListTile(
                  key: const Key('reasoning_mode_checkbox'),
                  title: const Text('Режим рассуждения'),
                  subtitle: const Text('До 10 уточняющих вопросов, маркер окончания будет скрыт для пользователя'),
                  value: _currentSettings.reasoningMode,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _currentSettings = _currentSettings.copyWith(reasoningMode: v);
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // History Depth
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Глубина истории',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Количество последних сообщений в контексте'),
                        Text('${/* display */ _currentSettings.historyDepth}')
                      ],
                    ),
                    Slider(
                      key: const Key('history_depth_slider'),
                      value: _currentSettings.historyDepth.toDouble().clamp(0, 100),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: _currentSettings.historyDepth.toString(),
                      onChanged: (v) {
                        setState(() {
                          _currentSettings = _currentSettings.copyWith(historyDepth: v.round());
                        });
                      },
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Подсказка: больше — точнее контекст, но выше расход токенов. Рекомендуется 10–40.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Neural Network Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Нейросеть',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<NeuralNetwork>(
                      value: _currentSettings.selectedNetwork,
                      items: NeuralNetwork.values.map((network) {
                        return DropdownMenuItem<NeuralNetwork>(
                          value: network,
                          child: Text(network == NeuralNetwork.deepseek
                              ? 'DeepSeek'
                              : 'YandexGPT'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _currentSettings = _currentSettings.copyWith(
                              selectedNetwork: value,
                            );
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Response Format Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Формат ответа',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<ResponseFormat>(
                      value: _currentSettings.responseFormat,
                      items: ResponseFormat.values.map((format) {
                        return DropdownMenuItem<ResponseFormat>(
                          value: format,
                          child: Text(format == ResponseFormat.text
                              ? 'Текст'
                              : 'JSON схема'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _currentSettings = _currentSettings.copyWith(
                              responseFormat: value,
                            );
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                    if (_currentSettings.responseFormat == ResponseFormat.json) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'JSON схема (опционально)',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('json_schema_field'),
                        controller: _jsonSchemaController,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Введите JSON схему...',
                        ),
                        onChanged: (value) {
                          _currentSettings = _currentSettings.copyWith(
                            customJsonSchema: value.isEmpty ? null : value,
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // MCP Provider Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Выбор MCP',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: const Text('Github MCP'),
                      value: _currentSettings.isGithubMcpEnabled,
                      onChanged: (bool? value) {
                        setState(() {
                          final updatedProviders = Set<MCPProvider>.from(_currentSettings.enabledMCPProviders);
                          if (value == true) {
                            updatedProviders.add(MCPProvider.github);
                          } else {
                            updatedProviders.remove(MCPProvider.github);
                          }
                          _currentSettings = _currentSettings.copyWith(
                            enabledMCPProviders: updatedProviders,
                          );
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (_currentSettings.isGithubMcpEnabled) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.blue[600],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Токен GitHub MCP',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Токен для GitHub MCP берется из файла .env.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Пожалуйста, добавьте GITHUB_MCP_TOKEN в .env файл для использования GitHub MCP.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  _isGithubTokenValid ? Icons.check_circle : Icons.error,
                                  color: _isGithubTokenValid ? Colors.green : Colors.red,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isGithubTokenValid ? '✅ Токен найден и действителен' : '❌ Токен не найден или недействителен',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _isGithubTokenValid ? Colors.green : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'GitHub MCP будет использоваться для обогащения контекста при запросах, связанных с GitHub репозиториями.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Быстрый тест: создать GitHub Issue',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _repoOwnerController,
                                      decoration: const InputDecoration(
                                        labelText: 'Владелец (owner)',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _repoNameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Репозиторий (repo)',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _issueTitleController,
                                decoration: const InputDecoration(
                                  labelText: 'Заголовок issue',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _issueBodyController,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Описание (опционально)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: (!_isGithubTokenValid || _isCreatingIssue)
                                      ? null
                                      : _handleCreateIssue,
                                  icon: _isCreatingIssue
                                      ? const SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.add_task),
                                  label: Text(_isCreatingIssue
                                      ? 'Создание...'
                                      : 'Создать issue'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
