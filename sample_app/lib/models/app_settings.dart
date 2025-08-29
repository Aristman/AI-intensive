
enum NeuralNetwork { deepseek, yandexgpt, tinylama }

enum ResponseFormat { text, json }

enum MCPProvider { github }

class AppSettings {
  final NeuralNetwork selectedNetwork;
  final ResponseFormat responseFormat;
  final String? customJsonSchema;
  final String systemPrompt;
  final int historyDepth; // количество последних сообщений, передаваемых в контекст
  final bool reasoningMode; // режим рассуждения
  // Параметры LLM (раздельно по провайдерам)
  final double yandexTemperature; // 0..1
  final int yandexMaxTokens;
  final double deepseekTemperature; // 0..2
  final int deepseekMaxTokens;
  final double tinylamaTemperature; // 0..1
  final int tinylamaMaxTokens;
  final String tinylamaEndpoint; // URL VPS сервера
  final Set<MCPProvider> enabledMCPProviders;
  final String? githubMcpToken;
  final bool useMcpServer; // использовать ли внешний MCP-сервер
  final String? mcpServerUrl; // адрес WebSocket MCP сервера
  // Настройки компрессии/сжатия контекста беседы
  final bool enableContextCompression; // включить ли сжатие истории через LLM
  final int compressAfterMessages; // порог количества сообщений для запуска сжатия
  final int compressKeepLastTurns; // сколько последних пар (user+assistant) оставить нетронутыми
  // Локальные настройки экрана GitHub
  final int githubReposListLimit; // количество элементов в списке репозиториев
  final int githubIssuesListLimit; // количество элементов в списке issues
  final int githubOtherListLimit; // количество элементов в прочих списках (PR, файлы PR и т.п.)
  final String? githubDefaultOwner; // дефолтный владелец для экрана GitHub
  final String? githubDefaultRepo; // дефолтный репозиторий для экрана GitHub

  const AppSettings({
    this.selectedNetwork = NeuralNetwork.deepseek,
    this.responseFormat = ResponseFormat.text,
    this.customJsonSchema,
    this.systemPrompt = 'You are a helpful assistant.',
    this.historyDepth = 20,
    this.reasoningMode = false,
    this.yandexTemperature = 0.3,
    this.yandexMaxTokens = 1500,
    this.deepseekTemperature = 1.0,
    this.deepseekMaxTokens = 1500,
    this.tinylamaTemperature = 0.7,
    this.tinylamaMaxTokens = 2048,
    this.tinylamaEndpoint = 'http://158.160.107.227:8000/v1/chat/completions',
    this.enabledMCPProviders = const {},
    this.githubMcpToken,
    this.useMcpServer = false,
    this.mcpServerUrl = 'ws://localhost:3001',
    this.enableContextCompression = true,
    this.compressAfterMessages = 40,
    this.compressKeepLastTurns = 6,
    this.githubReposListLimit = 5,
    this.githubIssuesListLimit = 10,
    this.githubOtherListLimit = 5,
    this.githubDefaultOwner,
    this.githubDefaultRepo,
  });

  // Create a copy with some changed fields
  AppSettings copyWith({
    NeuralNetwork? selectedNetwork,
    ResponseFormat? responseFormat,
    String? customJsonSchema,
    String? systemPrompt,
    int? historyDepth,
    bool? reasoningMode,
    double? yandexTemperature,
    int? yandexMaxTokens,
    double? deepseekTemperature,
    int? deepseekMaxTokens,
    double? tinylamaTemperature,
    int? tinylamaMaxTokens,
    String? tinylamaEndpoint,
    Set<MCPProvider>? enabledMCPProviders,
    String? githubMcpToken,
    bool? useMcpServer,
    String? mcpServerUrl,
    bool? enableContextCompression,
    int? compressAfterMessages,
    int? compressKeepLastTurns,
    int? githubReposListLimit,
    int? githubIssuesListLimit,
    int? githubOtherListLimit,
    String? githubDefaultOwner,
    String? githubDefaultRepo,
  }) {
    return AppSettings(
      selectedNetwork: selectedNetwork ?? this.selectedNetwork,
      responseFormat: responseFormat ?? this.responseFormat,
      customJsonSchema: customJsonSchema ?? this.customJsonSchema,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      historyDepth: historyDepth ?? this.historyDepth,
      reasoningMode: reasoningMode ?? this.reasoningMode,
      yandexTemperature: yandexTemperature ?? this.yandexTemperature,
      yandexMaxTokens: yandexMaxTokens ?? this.yandexMaxTokens,
      deepseekTemperature: deepseekTemperature ?? this.deepseekTemperature,
      deepseekMaxTokens: deepseekMaxTokens ?? this.deepseekMaxTokens,
      tinylamaTemperature: tinylamaTemperature ?? this.tinylamaTemperature,
      tinylamaMaxTokens: tinylamaMaxTokens ?? this.tinylamaMaxTokens,
      tinylamaEndpoint: tinylamaEndpoint ?? this.tinylamaEndpoint,
      enabledMCPProviders: enabledMCPProviders ?? this.enabledMCPProviders,
      githubMcpToken: githubMcpToken ?? this.githubMcpToken,
      useMcpServer: useMcpServer ?? this.useMcpServer,
      mcpServerUrl: mcpServerUrl ?? this.mcpServerUrl,
      enableContextCompression: enableContextCompression ?? this.enableContextCompression,
      compressAfterMessages: compressAfterMessages ?? this.compressAfterMessages,
      compressKeepLastTurns: compressKeepLastTurns ?? this.compressKeepLastTurns,
      githubReposListLimit: githubReposListLimit ?? this.githubReposListLimit,
      githubIssuesListLimit: githubIssuesListLimit ?? this.githubIssuesListLimit,
      githubOtherListLimit: githubOtherListLimit ?? this.githubOtherListLimit,
      githubDefaultOwner: githubDefaultOwner ?? this.githubDefaultOwner,
      githubDefaultRepo: githubDefaultRepo ?? this.githubDefaultRepo,
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
      'yandexTemperature': yandexTemperature,
      'yandexMaxTokens': yandexMaxTokens,
      'deepseekTemperature': deepseekTemperature,
      'deepseekMaxTokens': deepseekMaxTokens,
      'tinylamaTemperature': tinylamaTemperature,
      'tinylamaMaxTokens': tinylamaMaxTokens,
      'tinylamaEndpoint': tinylamaEndpoint,
      'githubMcpToken': githubMcpToken,
      'enabledMCPProviders': enabledMCPProviders.map((e) => e.toString().split('.').last).toList(),
      'useMcpServer': useMcpServer,
      'mcpServerUrl': mcpServerUrl,
      'enableContextCompression': enableContextCompression,
      'compressAfterMessages': compressAfterMessages,
      'compressKeepLastTurns': compressKeepLastTurns,
      'githubReposListLimit': githubReposListLimit,
      'githubIssuesListLimit': githubIssuesListLimit,
      'githubOtherListLimit': githubOtherListLimit,
      'githubDefaultOwner': githubDefaultOwner,
      'githubDefaultRepo': githubDefaultRepo,
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
      yandexTemperature: ((json['yandexTemperature'] as num?) ?? 0.3).toDouble(),
      yandexMaxTokens: (json['yandexMaxTokens'] as int?) ?? 1500,
      deepseekTemperature: ((json['deepseekTemperature'] as num?) ?? 1.0).toDouble(),
      deepseekMaxTokens: (json['deepseekMaxTokens'] as int?) ?? 1500,
      tinylamaTemperature: ((json['tinylamaTemperature'] as num?) ?? 0.7).toDouble(),
      tinylamaMaxTokens: (json['tinylamaMaxTokens'] as int?) ?? 2048,
      tinylamaEndpoint: (json['tinylamaEndpoint'] as String?) ?? 'http://158.160.107.227:8000/v1/chat/completions',
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
      enableContextCompression: (json['enableContextCompression'] as bool?) ?? true,
      compressAfterMessages: (json['compressAfterMessages'] as int?) ?? 40,
      compressKeepLastTurns: (json['compressKeepLastTurns'] as int?) ?? 6,
      githubReposListLimit: (json['githubReposListLimit'] as int?) ?? 5,
      githubIssuesListLimit: (json['githubIssuesListLimit'] as int?) ?? 10,
      githubOtherListLimit: (json['githubOtherListLimit'] as int?) ?? 5,
      githubDefaultOwner: json['githubDefaultOwner'] as String?,
      githubDefaultRepo: json['githubDefaultRepo'] as String?,
    );
  }

  // Helper methods
  String get selectedNetworkName {
    switch (selectedNetwork) {
      case NeuralNetwork.deepseek:
        return 'DeepSeek';
      case NeuralNetwork.yandexgpt:
        return 'YandexGPT';
      case NeuralNetwork.tinylama:
        return 'TinyLlama';
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
