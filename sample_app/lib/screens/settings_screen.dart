import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';
import 'package:sample_app/services/github_mcp_service.dart';
import 'package:sample_app/services/mcp_client.dart';

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
  // Controllers for quick GitHub Issue creation
  final _repoOwnerController = TextEditingController();
  final _repoNameController = TextEditingController();
  final _issueTitleController = TextEditingController();
  final _issueBodyController = TextEditingController();
  bool _isCreatingIssue = false;
  // MCP client and state
  final McpClient _mcpClient = McpClient();
  bool _mcpConnected = false;
  bool _mcpInitialized = false;
  bool _isCheckingMcp = false;
  final _mcpUrlController = TextEditingController();
  String? _mcpUrlErrorText; // отображение ошибки URL

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.initialSettings;
    _jsonSchemaController.text = _currentSettings.customJsonSchema ?? '';
    _systemPromptController.text = _currentSettings.systemPrompt;
    _mcpUrlController.text = _currentSettings.mcpServerUrl ?? '';
    // начальная валидация MCP URL
    _mcpUrlErrorText = _currentSettings.useMcpServer && !_isValidWebSocketUrl(_mcpUrlController.text.trim())
        ? 'Некорректный WebSocket URL (пример: ws://localhost:3001)'
        : null;
    // Сообщаем о начальных настройках (полезно для виджет-тестов)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onSettingsChanged(_currentSettings);
      }
    });
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

  Future<void> _handleCreateIssue() async {
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
      if (_currentSettings.useMcpServer) {
        // Ensure MCP connected and initialized
        if (!_mcpConnected) {
          await _connectAndInitMcp();
        }
        final resp = await _mcpClient.toolsCall('create_issue', {
          'owner': owner,
          'repo': repo,
          'title': title,
          'body': body,
        });
        final issue = (resp is Map && resp['result'] is Map)
            ? Map<String, dynamic>.from(resp['result'] as Map)
            : <String, dynamic>{};
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Issue создан (MCP): #${issue['number'] ?? '?'}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        if (!_isGithubTokenValid) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Сначала добавьте валидный GITHUB_MCP_TOKEN в .env или включите MCP сервер'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        final result = await _githubMcpService.createIssueFromEnv(owner, repo, title, body);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Issue создан: #${result['number']}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
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

  Future<void> _connectAndInitMcp() async {
    final url = _currentSettings.mcpServerUrl?.trim();
    if (url == null || url.isEmpty) {
      throw Exception('MCP URL не указан');
    }
    if (!_isValidWebSocketUrl(url)) {
      throw Exception('Некорректный MCP URL');
    }
    await _mcpClient.connect(url);
    setState(() {
      _mcpConnected = true;
    });
    await _mcpClient.initialize();
    setState(() {
      _mcpInitialized = true;
    });
  }

  Future<void> _checkMcp() async {
    setState(() => _isCheckingMcp = true);
    try {
      await _connectAndInitMcp();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MCP сервер доступен и инициализирован'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mcpConnected = false;
        _mcpInitialized = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось подключиться к MCP: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isCheckingMcp = false);
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
    _mcpUrlController.dispose();
    _mcpClient.close();
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

  bool _isValidWebSocketUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    try {
      final u = Uri.parse(url.trim());
      return (u.scheme == 'ws' || u.scheme == 'wss') && (u.host.isNotEmpty);
    } catch (_) {
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

    // Сохраняем без ожидания результата (во избежание зависаний в тестовой среде)
    // ignore: unawaited_futures
    _settingsService.saveSettings(_currentSettings);
    if (mounted) {
      widget.onSettingsChanged(_currentSettings);
      Navigator.of(context).pop(_currentSettings);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: SettingsScreen.settingsScreenKey,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Настройки', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отменить'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save),
                      label: const Text('Сохранить'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
            // Neural Network Selection (moved to top so it's visible in tests)
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
                          // Уведомляем об изменении сразу, чтобы тесты получили актуальные настройки
                          widget.onSettingsChanged(_currentSettings);
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
            // System Prompt
            if (_currentSettings.responseFormat == ResponseFormat.text)
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
                        Text('Сообщений: ${_currentSettings.historyDepth}'),
                        SizedBox(
                          width: 200,
                          child: Slider(
                            value: _currentSettings.historyDepth.toDouble(),
                            min: 1,
                            max: 100,
                            divisions: 99,
                            label: _currentSettings.historyDepth.toString(),
                            onChanged: (v) {
                              final val = v.round().clamp(1, 100);
                              setState(() {
                                _currentSettings = _currentSettings.copyWith(historyDepth: val);
                              });
                              widget.onSettingsChanged(_currentSettings);
                            },
                          ),
                        ),
                      ],
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
            // (Neural Network selection moved above)
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
                          widget.onSettingsChanged(_currentSettings);
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
                          widget.onSettingsChanged(_currentSettings);
                        },
                      ),
                    ],
                    
                    if (_currentSettings.useMcpServer) ...[
                      TextField(
                        key: const Key('mcp_url_field'),
                        enabled: _currentSettings.useMcpServer,
                        decoration: InputDecoration(
                          labelText: 'MCP WebSocket URL (например, ws://localhost:3001)',
                          border: const OutlineInputBorder(),
                          errorText: _mcpUrlErrorText,
                          helperText: _mcpUrlErrorText == null ? 'Подключение выполняется по JSON-RPC 2.0' : null,
                        ),
                        controller: _mcpUrlController,
                        onChanged: (v) {
                          final valid = _isValidWebSocketUrl(v);
                          setState(() {
                            _currentSettings = _currentSettings.copyWith(mcpServerUrl: v);
                            _mcpUrlErrorText = valid ? null : 'Некорректный WebSocket URL (пример: ws://localhost:3001)';
                          });
                          widget.onSettingsChanged(_currentSettings);
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            key: const Key('check_mcp_button'),
                            onPressed: !_currentSettings.useMcpServer || _isCheckingMcp || _mcpUrlErrorText != null
                                ? null
                                : _checkMcp,
                            icon: _isCheckingMcp
                                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.link),
                            label: Text(_isCheckingMcp ? 'Проверка...' : 'Проверить MCP'),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            _mcpConnected && _mcpInitialized ? Icons.check_circle : Icons.error,
                            color: _mcpConnected && _mcpInitialized ? Colors.green : Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _mcpConnected && _mcpInitialized
                                ? 'Подключено и инициализировано'
                                : (_mcpUrlErrorText != null ? 'Неверный URL' : 'Не подключено'),
                            style: TextStyle(
                              color: _mcpConnected && _mcpInitialized ? Colors.green : (_mcpUrlErrorText != null ? Colors.orange : Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ],
                    CheckboxListTile(
                      key: const Key('use_mcp_server_checkbox'),
                      title: const Text('Использовать MCP сервер'),
                      value: _currentSettings.useMcpServer,
                      onChanged: (bool? value) {
                        setState(() {
                          final use = value ?? false;
                          _currentSettings = _currentSettings.copyWith(useMcpServer: use);
                          // Пересчитать ошибку URL при включении
                          _mcpUrlErrorText = use && !_isValidWebSocketUrl(_mcpUrlController.text.trim())
                              ? 'Некорректный WebSocket URL (пример: ws://localhost:3001)'
                              : null;
                        });
                        widget.onSettingsChanged(_currentSettings);
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      key: const Key('github_mcp_checkbox'),
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
                        widget.onSettingsChanged(_currentSettings);
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (_currentSettings.isGithubMcpEnabled || _currentSettings.useMcpServer) ...[
                      const SizedBox(height: 16),
                      Container(
                        key: const Key('mcp_info_container'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
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
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final narrow = constraints.maxWidth < 480;
                                  final children = <Widget>[
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
                                  ];
                                  return narrow
                                      ? Column(
                                          children: [
                                            children[0],
                                            const SizedBox(height: 8),
                                            children[1],
                                          ],
                                        )
                                      : Row(children: children);
                                },
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
                                  onPressed: _isCreatingIssue
                                      ? null
                                      : (_currentSettings.useMcpServer
                                          ? (_mcpUrlErrorText == null ? _handleCreateIssue : null)
                                          : (_isGithubTokenValid ? _handleCreateIssue : null)),
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
      ],
    ),
  ),
);
  }
}
