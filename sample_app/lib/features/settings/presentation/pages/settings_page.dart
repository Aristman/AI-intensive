import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/enums/response_format.dart';
import '../providers/settings_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // API Key
                _buildSectionHeader('API Configuration'),
                _buildTextField(
                  label: 'API Key',
                  value: settings.apiKey,
                  onChanged: (value) => settings.updateApiKey(value),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                _buildTextField(
                  label: 'Base URL',
                  value: settings.baseUrl,
                  onChanged: (value) => settings.updateBaseUrl(value),
                ),
                
                const Divider(height: 32),
                
                // Model Settings
                _buildSectionHeader('Model Settings'),
                _buildDropdownField(
                  label: 'Model',
                  value: settings.selectedModel,
                  items: const [
                    DropdownMenuItem(value: 'deepseek-chat', child: Text('DeepSeek Chat')),
                    DropdownMenuItem(value: 'yandexgpt', child: Text('YandexGPT')),
                  ],
                  onChanged: (value) => settings.updateSelectedModel(value ?? 'deepseek-chat'),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'System Prompt',
                  value: settings.systemPrompt,
                  onChanged: (value) => settings.updateSystemPrompt(value),
                  maxLines: 3,
                ),
                
                const Divider(height: 32),
                
                // Response Format
                _buildSectionHeader('Response Format'),
                _buildRadioListTile(
                  title: 'Text',
                  value: ResponseFormat.text,
                  groupValue: settings.responseFormat,
                  onChanged: (value) => settings.updateResponseFormat(value as ResponseFormat),
                ),
                _buildRadioListTile(
                  title: 'JSON',
                  value: ResponseFormat.json,
                  groupValue: settings.responseFormat,
                  onChanged: (value) => settings.updateResponseFormat(value as ResponseFormat),
                ),
                if (settings.responseFormat == ResponseFormat.json) ...[
                  const SizedBox(height: 8),
                  _buildTextField(
                    label: 'JSON Schema (optional)',
                    value: settings.customJsonSchema ?? '',
                    onChanged: (value) => settings.updateCustomJsonSchema(value.isEmpty ? null : value),
                    maxLines: 5,
                    hintText: '{\n  "key": "value"\n}',
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    int maxLines = 1,
    bool obscureText = false,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          hintText: hintText,
          alignLabelWithHint: true,
        ),
        controller: TextEditingController(text: value)..selection = TextSelection.collapsed(offset: value.length),
        onChanged: onChanged,
        maxLines: maxLines,
        obscureText: obscureText,
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: DropdownButtonFormField<T>(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        value: value,
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildRadioListTile<T>({
    required String title,
    required T value,
    required T? groupValue,
    required ValueChanged<T?> onChanged,
  }) {
    return RadioListTile<T>(
      title: Text(title),
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}
