import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/models/app_settings.dart';

/// Реализация юзкейса для YandexGPT Chat Completions API
/// Документация: https://yandex.cloud/ru/docs/foundation-models/quickstart/yandexgpt
class YandexGptUseCase implements LlmUseCase {
  // Базовый URL берем из .env: YANDEX_GPT_BASE_URL
  // Фоллбэк — официальный endpoint.
  String get _endpoint => dotenv.env['YANDEX_GPT_BASE_URL'] ??
      'https://llm.api.cloud.yandex.net/foundationModels/v1/chat/completions';

  String get _apiKey => dotenv.env['YANDEX_API_KEY'] ?? '';
  String get _folderId => dotenv.env['YANDEX_FOLDER_ID'] ?? '';

  String get _modelUri {
    // По умолчанию используем yandexgpt/latest; можно заменить на yandexgpt-lite/latest
    final folder = _folderId;
    return 'gpt://$folder/yandexgpt/latest';
  }

  @override
  Future<String> complete({
    required List<Map<String, String>> messages,
    required AppSettings settings,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('API ключ Yandex не найден. Добавьте YANDEX_API_KEY в assets/.env');
    }
    if (_folderId.isEmpty) {
      throw Exception('Не указан YANDEX_FOLDER_ID в assets/.env');
    }

    // Конвертируем наше сообщение из {'role': 'user', 'content': '...'} в формат Yandex {'role': 'user', 'text': '...'}
    final ycMessages = [
      for (final m in messages)
        {
          'role': m['role'],
          'text': m['content'],
        }
    ];

    final body = jsonEncode({
      'modelUri': _modelUri,
      'completionOptions': {
        'stream': false,
        'temperature': 0.3,
        'maxTokens': 1500,
      },
      'messages': ycMessages,
    });

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        // Авторизация через API-ключ
        'Authorization': 'Api-Key $_apiKey',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка YandexGPT: ${response.statusCode} ${response.body}');
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    // Формат: { result: { alternatives: [ { message: { role, text } } ] } }
    final text = data['result']?['alternatives']?[0]?['message']?['text'];
    if (text is String && text.isNotEmpty) {
      return text;
    }
    throw Exception('Пустой ответ от YandexGPT');
  }
}
