import 'package:json_annotation/json_annotation.dart';

enum NeuralNetwork { deepseek, yandexgpt }

enum ResponseFormat { text, json }

class AppSettings {
  final NeuralNetwork selectedNetwork;
  final ResponseFormat responseFormat;
  final String? customJsonSchema;
  final String systemPrompt;
  final int historyDepth; // количество последних сообщений, передаваемых в контекст

  const AppSettings({
    this.selectedNetwork = NeuralNetwork.deepseek,
    this.responseFormat = ResponseFormat.text,
    this.customJsonSchema,
    this.systemPrompt = 'You are a helpful assistant.',
    this.historyDepth = 20,
  });

  // Create a copy with some changed fields
  AppSettings copyWith({
    NeuralNetwork? selectedNetwork,
    ResponseFormat? responseFormat,
    String? customJsonSchema,
    String? systemPrompt,
    int? historyDepth,
  }) {
    return AppSettings(
      selectedNetwork: selectedNetwork ?? this.selectedNetwork,
      responseFormat: responseFormat ?? this.responseFormat,
      customJsonSchema: customJsonSchema ?? this.customJsonSchema,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      historyDepth: historyDepth ?? this.historyDepth,
    );
  }

  // Convert to JSON for serialization
  Map<String, dynamic> toJson() {
    return {
      'selectedNetwork': selectedNetwork.toString().split('.').last,
      'responseFormat': responseFormat.toString().split('.').last,
      'customJsonSchema': customJsonSchema,
      'systemPrompt': systemPrompt,
      'historyDepth': historyDepth,
    };
  }

  // Create from JSON for deserialization
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      selectedNetwork: NeuralNetwork.values.firstWhere(
        (e) => e.toString() == 'NeuralNetwork.${json['selectedNetwork']}',
        orElse: () => NeuralNetwork.deepseek,
      ),
      responseFormat: ResponseFormat.values.firstWhere(
        (e) => e.toString() == 'ResponseFormat.${json['responseFormat']}',
        orElse: () => ResponseFormat.text,
      ),
      customJsonSchema: json['customJsonSchema'],
      systemPrompt: (json['systemPrompt'] as String?) ?? 'You are a helpful assistant.',
      historyDepth: (json['historyDepth'] as int?) ?? 20,
    );
  }

  // Helper methods
  String get selectedNetworkName {
    switch (selectedNetwork) {
      case NeuralNetwork.deepseek:
        return 'DeepSeek';
      case NeuralNetwork.yandexgpt:
        return 'YandexGPT';
    }
  }

  String get responseFormatName {
    switch (responseFormat) {
      case ResponseFormat.text:
        return 'Text';
      case ResponseFormat.json:
        return 'JSON';
    }
  }
}

// Run this command to generate the .g.dart file:
// flutter pub run build_runner build
