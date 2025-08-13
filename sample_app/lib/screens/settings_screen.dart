import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sample_app/models/app_settings.dart';
import 'package:sample_app/services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  static const Key settingsScreenKey = Key('settings_screen');
  final AppSettings initialSettings;
  final Function(AppSettings) onSettingsChanged;

  const SettingsScreen({
    Key? key,
    required this.initialSettings,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _currentSettings;
  final _settingsService = SettingsService();
  final _jsonSchemaController = TextEditingController();
  final _systemPromptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.initialSettings;
    _jsonSchemaController.text = _currentSettings.customJsonSchema ?? '';
    _systemPromptController.text = _currentSettings.systemPrompt;
  }

  @override
  void dispose() {
    _jsonSchemaController.dispose();
    _systemPromptController.dispose();
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
          ],
        ),
      ),
    );
  }
}
