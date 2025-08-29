import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/models/app_settings.dart';

/// Реализация юзкейса для TinyLlama VPS модели
/// Использует OpenAI-compatible API без авторизации
class TinyLlamaUseCase implements LlmUseCase {
  @override
  Future<String> complete({
    required List<Map<String, String>> messages,
    required AppSettings settings,
  }) async {
    // Получаем параметры из настроек
    final String endpoint = settings.tinylamaEndpoint;
    final double temperature = settings.tinylamaTemperature.clamp(0.0, 1.0);
    final int maxTokens = settings.tinylamaMaxTokens > 0 ? settings.tinylamaMaxTokens : 2048;

    // Валидация endpoint
    if (endpoint.isEmpty) {
      throw Exception('TinyLlama endpoint не задан в настройках');
    }

    // Конвертируем сообщения в формат OpenAI
    final openAiMessages = messages.map((msg) {
      return {
        'role': msg['role'],
        'content': msg['content'],
      };
    }).toList();

    // Формируем тело запроса в формате OpenAI Chat Completions
    final requestBody = {
      'model': 'TinyLlama-1.1B-Chat',
      'messages': openAiMessages,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': false,
    };

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Ошибка TinyLlama API: ${response.statusCode} ${response.body}'
        );
      }

      // Парсим ответ в формате OpenAI
      final Map<String, dynamic> data = jsonDecode(response.body);

      // Извлекаем контент из ответа
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('Пустой ответ от TinyLlama API: отсутствуют choices');
      }

      final firstChoice = choices[0] as Map<String, dynamic>;
      final message = firstChoice['message'] as Map<String, dynamic>?;
      if (message == null) {
        throw Exception('Пустой ответ от TinyLlama API: отсутствует message');
      }

      final content = message['content'] as String?;
      if (content == null || content.isEmpty) {
        throw Exception('Пустой контент в ответе от TinyLlama API');
      }

      return content;

    } catch (e) {
      if (e is http.ClientException) {
        throw Exception('Ошибка сети при подключении к TinyLlama: ${e.message}');
      } else if (e is FormatException) {
        throw Exception('Ошибка парсинга ответа от TinyLlama: ${e.message}');
      } else {
        rethrow;
      }
    }
  }
}
