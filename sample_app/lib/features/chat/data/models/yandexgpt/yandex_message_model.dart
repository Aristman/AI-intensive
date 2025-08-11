import 'package:equatable/equatable.dart';

class YandexMessageModel extends Equatable {
  final String role;
  final String text;

  const YandexMessageModel({
    required this.role,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
      };

  factory YandexMessageModel.fromJson(Map<String, dynamic> json) {
    return YandexMessageModel(
      role: json['role'],
      text: json['text'],
    );
  }

  @override
  List<Object?> get props => [role, text];
}

class YandexRequestModel extends Equatable {
  final String modelUri;
  final YandexCompletionOptions completionOptions;
  final List<YandexMessageModel> messages;

  const YandexRequestModel({
    required this.modelUri,
    required this.completionOptions,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
        'modelUri': modelUri,
        'completionOptions': completionOptions.toJson(),
        'messages': messages.map((e) => e.toJson()).toList(),
      };

  @override
  List<Object?> get props => [modelUri, completionOptions, messages];
}

class YandexCompletionOptions extends Equatable {
  final bool stream;
  final double temperature;
  final int maxTokens;

  const YandexCompletionOptions({
    this.stream = false,
    this.temperature = 0.6,
    this.maxTokens = 2000,
  });

  Map<String, dynamic> toJson() => {
        'stream': stream,
        'temperature': temperature,
        'maxTokens': maxTokens,
      };

  @override
  List<Object?> get props => [stream, temperature, maxTokens];
}

class YandexResponseModel extends Equatable {
  final YandexResult result;

  const YandexResponseModel({
    required this.result,
  });

  factory YandexResponseModel.fromJson(Map<String, dynamic> json) {
    return YandexResponseModel(
      result: YandexResult.fromJson(json['result']),
    );
  }

  @override
  List<Object?> get props => [result];
}

class YandexResult extends Equatable {
  final List<YandexMessageModel> alternatives;
  final YandexUsage usage;
  final String modelVersion;

  const YandexResult({
    required this.alternatives,
    required this.usage,
    required this.modelVersion,
  });

  factory YandexResult.fromJson(Map<String, dynamic> json) {
    return YandexResult(
      alternatives: (json['alternatives'] as List)
          .map((e) => YandexMessageModel.fromJson(e))
          .toList(),
      usage: YandexUsage.fromJson(json['usage']),
      modelVersion: json['modelVersion'],
    );
  }

  @override
  List<Object?> get props => [alternatives, usage, modelVersion];
}

class YandexUsage extends Equatable {
  final int inputTextTokens;
  final int completionTokens;
  final int totalTokens;

  const YandexUsage({
    required this.inputTextTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  factory YandexUsage.fromJson(Map<String, dynamic> json) {
    return YandexUsage(
      inputTextTokens: json['inputTextTokens'],
      completionTokens: json['completionTokens'],
      totalTokens: json['totalTokens'],
    );
  }

  @override
  List<Object?> get props => [inputTextTokens, completionTokens, totalTokens];
}
