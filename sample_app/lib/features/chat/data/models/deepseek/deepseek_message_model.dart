import 'package:equatable/equatable.dart';

class DeepSeekMessageModel extends Equatable {
  final String role;
  final String content;

  const DeepSeekMessageModel({
    required this.role,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };

  factory DeepSeekMessageModel.fromJson(Map<String, dynamic> json) {
    return DeepSeekMessageModel(
      role: json['role'],
      content: json['content'],
    );
  }

  @override
  List<Object?> get props => [role, content];
}

class DeepSeekRequestModel extends Equatable {
  final String model;
  final List<DeepSeekMessageModel> messages;
  final bool stream;
  final Map<String, dynamic>? responseFormat;

  const DeepSeekRequestModel({
    required this.model,
    required this.messages,
    this.stream = false,
    this.responseFormat,
  });

  Map<String, dynamic> toJson() => {
        'model': model,
        'messages': messages.map((e) => e.toJson()).toList(),
        'stream': stream,
        if (responseFormat != null) 'response_format': responseFormat,
      };

  @override
  List<Object?> get props => [model, messages, stream, responseFormat];
}

class DeepSeekResponseModel extends Equatable {
  final String id;
  final String object;
  final int created;
  final String model;
  final List<dynamic> choices;
  final Map<String, dynamic>? usage;

  const DeepSeekResponseModel({
    required this.id,
    required this.object,
    required this.created,
    required this.model,
    required this.choices,
    this.usage,
  });

  factory DeepSeekResponseModel.fromJson(Map<String, dynamic> json) {
    return DeepSeekResponseModel(
      id: json['id'],
      object: json['object'],
      created: json['created'],
      model: json['model'],
      choices: json['choices'],
      usage: json['usage'],
    );
  }

  @override
  List<Object?> get props => [id, object, created, model, choices, usage];
}
