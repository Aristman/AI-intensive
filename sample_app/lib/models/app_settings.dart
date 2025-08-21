
enum NeuralNetwork { deepseek, yandexgpt }

enum ResponseFormat { text, json }

enum MCPProvider { github }

class AppSettings {
  final NeuralNetwork selectedNetwork;
  final ResponseFormat responseFormat;
  final String? customJsonSchema;
  final String systemPrompt;
  final int historyDepth; // количество последних сообщений, передаваемых в контекст
  final bool reasoningMode; // режим рассуждения
  final Set<MCPProvider> enabledMCPProviders;
  final String? githubMcpToken;
  final bool useMcpServer; // использовать ли внешний MCP-сервер
  final String? mcpServerUrl; // адрес WebSocket MCP сервера

  const AppSettings({
    this.selectedNetwork = NeuralNetwork.deepseek,
    this.responseFormat = ResponseFormat.text,
    this.customJsonSchema,
    this.systemPrompt = 'You are a helpful assistant.',
    this.historyDepth = 20,
    this.reasoningMode = false,
    this.enabledMCPProviders = const {},
    this.githubMcpToken,
    this.useMcpServer = false,
    this.mcpServerUrl = 'ws://localhost:3001',
  });

  // Create a copy with some changed fields
  AppSettings copyWith({
    NeuralNetwork? selectedNetwork,
    ResponseFormat? responseFormat,
    String? customJsonSchema,
    String? systemPrompt,
    int? historyDepth,
    bool? reasoningMode,
    Set<MCPProvider>? enabledMCPProviders,
    String? githubMcpToken,
    bool? useMcpServer,
    String? mcpServerUrl,
  }) {
    return AppSettings(
      selectedNetwork: selectedNetwork ?? this.selectedNetwork,
      responseFormat: responseFormat ?? this.responseFormat,
      customJsonSchema: customJsonSchema ?? this.customJsonSchema,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      historyDepth: historyDepth ?? this.historyDepth,
      reasoningMode: reasoningMode ?? this.reasoningMode,
      enabledMCPProviders: enabledMCPProviders ?? this.enabledMCPProviders,
      githubMcpToken: githubMcpToken ?? this.githubMcpToken,
      useMcpServer: useMcpServer ?? this.useMcpServer,
      mcpServerUrl: mcpServerUrl ?? this.mcpServerUrl,
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
      'reasoningMode': reasoningMode,
      'githubMcpToken': githubMcpToken,
      'enabledMCPProviders': enabledMCPProviders.map((e) => e.toString().split('.').last).toList(),
      'useMcpServer': useMcpServer,
      'mcpServerUrl': mcpServerUrl,
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
      reasoningMode: (json['reasoningMode'] as bool?) ?? false,
      githubMcpToken: json['githubMcpToken'] as String?,
      enabledMCPProviders: ((json['enabledMCPProviders'] as List?) ?? const <dynamic>[]) 
          .map((e) => e.toString())
          .map((name) => MCPProvider.values.firstWhere(
                (p) => p.toString() == 'MCPProvider.$name',
                orElse: () => MCPProvider.github,
              ))
          .toSet(),
      useMcpServer: (json['useMcpServer'] as bool?) ?? false,
      mcpServerUrl: (json['mcpServerUrl'] as String?) ?? 'ws://localhost:3001',
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

  bool get isGithubMcpEnabled => enabledMCPProviders.contains(MCPProvider.github);
}

// Run this command to generate the .g.dart file:
// flutter pub run build_runner build
