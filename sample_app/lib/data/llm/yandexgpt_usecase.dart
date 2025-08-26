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
      'https://llm.api.cloud.yandex.net/foundationModels/v1/completion';

  String get _iamToken =>
      dotenv.env['YANDEX_IAM_TOKEN'] ?? dotenv.env['YC_IAM_TOKEN'] ?? '';
  String get _apiKey => dotenv.env['YANDEX_API_KEY'] ?? '';
  String get _folderId => dotenv.env['YANDEX_FOLDER_ID'] ?? '';

  String get _modelUri {
    // Позволяем переопределить модель через .env (YANDEX_MODEL_URI), иначе используем дефолт
    final override = dotenv.env['YANDEX_MODEL_URI'];
    if (override != null && override.isNotEmpty) return override;
    // По умолчанию используем yandexgpt/latest; можно заменить на yandexgpt-lite/latest
    final folder = _folderId;
    return 'gpt://$folder/yandexgpt';
  }

  @override
  Future<String> complete({
    required List<Map<String, String>> messages,
    required AppSettings settings,
  }) async {
    // Требуем либо IAM токен (предпочтительно), либо Api-Key (временный fallback)
    if (_iamToken.isEmpty && _apiKey.isEmpty) {
      throw Exception('Не найден Yandex IAM токен или API ключ. Укажите YANDEX_IAM_TOKEN (предпочтительно) или YANDEX_API_KEY в assets/.env');
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

    // Настройки генерации
    final double temperature = settings.yandexTemperature.clamp(0.0, 1.0);
    final int maxTokens = settings.yandexMaxTokens > 0 ? settings.yandexMaxTokens : 1;

    final body = jsonEncode({
      'modelUri': _modelUri,
      'completionOptions': {
        'stream': false,
        'temperature': temperature,
        'maxTokens': maxTokens,
      },
      'messages': ycMessages,
    });

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (_iamToken.isNotEmpty) ...{
        'Authorization': 'Bearer $_iamToken',
      } else ...{
        // Временный fallback на Api-Key (менее предпочтительно)
        'Authorization': 'Api-Key $_apiKey',
        'x-folder-id': _folderId,
      }
    };

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: headers,
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
