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

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.initialSettings;
    _jsonSchemaController.text = _currentSettings.customJsonSchema ?? '';
  }

  @override
  void dispose() {
    _jsonSchemaController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
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
