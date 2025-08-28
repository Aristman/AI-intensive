import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:telegram_summarizer/domain/llm_usecase.dart';

/// Реализация YandexGPT Chat Completions API
/// Документация: https://yandex.cloud/ru/docs/foundation-models/quickstart/yandexgpt
class YandexGptUseCase implements LlmUseCase {
  final String endpoint;
  YandexGptUseCase({
    this.endpoint =
        'https://llm.api.cloud.yandex.net/foundationModels/v1/completion',
  });

  String _resolveModelUri(String modelOrUri, String folderId) {
    if (modelOrUri.startsWith('gpt://')) return modelOrUri;
    // Принимаем короткие имена: yandexgpt, yandexgpt-lite
    return 'gpt://$folderId/$modelOrUri';
  }

  @override
  Future<String> complete({
    required List<Map<String, String>> messages,
    required String modelUri,
    required String iamToken,
    required String apiKey,
    required String folderId,
    double temperature = 0.2,
    int maxTokens = 128,
    http.Client? client,
  }) async {
    if ((iamToken.isEmpty) && apiKey.isEmpty) {
      throw Exception(
          'Укажите IAM-токен или API-ключ для YandexGPT в настройках');
    }
    if (folderId.isEmpty) {
      throw Exception('Укажите Folder ID (x-folder-id) для Yandex Cloud');
    }

    final ycMessages = [
      for (final m in messages)
        {
          'role': m['role'],
          'text': m['content'],
        }
    ];

    final body = jsonEncode({
      'modelUri': _resolveModelUri(modelUri, folderId),
      'completionOptions': {
        'stream': false,
        'temperature': temperature.clamp(0.0, 1.0),
        'maxTokens': maxTokens > 0 ? maxTokens : 1,
      },
      'messages': ycMessages,
    });

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (iamToken.isNotEmpty) 'Authorization': 'Bearer $iamToken',
      if (iamToken.isEmpty && apiKey.isNotEmpty) ...{
        'Authorization': 'Api-Key $apiKey',
        'x-folder-id': folderId,
      }
    };

    final cli = client ?? http.Client();
    try {
      final resp = await cli.post(Uri.parse(endpoint), headers: headers, body: body);
      if (resp.statusCode != 200) {
        throw Exception('Ошибка YandexGPT: ${resp.statusCode} ${resp.body}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final text = data['result']?['alternatives']?[0]?['message']?['text'];
      if (text is String && text.isNotEmpty) return text;
      throw Exception('Пустой ответ от YandexGPT');
    } finally {
      if (client == null) cli.close();
    }
  }
}
