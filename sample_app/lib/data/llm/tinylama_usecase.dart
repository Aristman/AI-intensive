import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/models/app_settings.dart';

/// Реализация юзкейса для TinyLlama VPS модели
/// Использует OpenAI-compatible API без авторизации
class TinyLlamaUseCase implements LlmUseCase {
  final http.Client _client;

  /// Конструктор с опциональным клиентом для тестирования
  TinyLlamaUseCase({http.Client? client}) : _client = client ?? http.Client();
  @override
  Future<String> complete({
    required List<Map<String, String>> messages,
    required AppSettings settings,
  }) async {
    log('TinyLlamaUseCase.complete: Начинаем обработку запроса', name: 'TinyLlamaUseCase');

    // Получаем параметры из настроек
    final String endpoint = settings.tinylamaEndpoint;
    final double temperature = settings.tinylamaTemperature.clamp(0.0, 1.0);
    final int maxTokens = settings.tinylamaMaxTokens > 0 ? settings.tinylamaMaxTokens : 2048;

    log('TinyLlamaUseCase: Параметры - endpoint: $endpoint, temperature: $temperature, maxTokens: $maxTokens', name: 'TinyLlamaUseCase');
    log('TinyLlamaUseCase: Сообщений для обработки: ${messages.length}', name: 'TinyLlamaUseCase');

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

    log('TinyLlamaUseCase: Отправляем запрос к $endpoint', name: 'TinyLlamaUseCase');
    log('TinyLlamaUseCase: Тело запроса: ${jsonEncode(requestBody)}', name: 'TinyLlamaUseCase');

    try {
      final response = await _client.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      log('TinyLlamaUseCase: Получен ответ с кодом ${response.statusCode}', name: 'TinyLlamaUseCase');

      if (response.statusCode != 200) {
        log('TinyLlamaUseCase: Ошибка HTTP ${response.statusCode}: ${response.body}', name: 'TinyLlamaUseCase');
        throw Exception(
          'Ошибка TinyLlama API: ${response.statusCode} ${response.body}'
        );
      }

      log('TinyLlamaUseCase: Успешный ответ, парсим JSON', name: 'TinyLlamaUseCase');
      // Парсим ответ в формате OpenAI
      final Map<String, dynamic> data = jsonDecode(response.body);

      // Извлекаем контент из ответа
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        log('TinyLlamaUseCase: Ошибка - choices отсутствуют в ответе', name: 'TinyLlamaUseCase');
        throw Exception('Пустой ответ от TinyLlama API: отсутствуют choices');
      }

      final firstChoice = choices[0] as Map<String, dynamic>;
      final message = firstChoice['message'] as Map<String, dynamic>?;
      if (message == null) {
        log('TinyLlamaUseCase: Ошибка - message отсутствует в ответе', name: 'TinyLlamaUseCase');
        throw Exception('Пустой ответ от TinyLlama API: отсутствует message');
      }

      final content = message['content'] as String?;
      if (content == null || content.isEmpty) {
        log('TinyLlamaUseCase: Ошибка - content пустой или отсутствует', name: 'TinyLlamaUseCase');
        throw Exception('Пустой контент в ответе от TinyLlama API');
      }

      log('TinyLlamaUseCase: Успешно извлечен контент длиной ${content.length} символов', name: 'TinyLlamaUseCase');
      return content;

    } catch (e) {
      log('TinyLlamaUseCase: Произошла ошибка: ${e.toString()}', name: 'TinyLlamaUseCase');
      if (e is http.ClientException) {
        log('TinyLlamaUseCase: Сетевая ошибка: ${e.message}', name: 'TinyLlamaUseCase');
        throw Exception('Ошибка сети при подключении к TinyLlama: ${e.message}');
      } else if (e is FormatException) {
        log('TinyLlamaUseCase: Ошибка парсинга JSON: ${e.message}', name: 'TinyLlamaUseCase');
        throw Exception('Ошибка парсинга ответа от TinyLlama: ${e.message}');
      } else {
        log('TinyLlamaUseCase: Неизвестная ошибка: ${e.runtimeType}', name: 'TinyLlamaUseCase');
        rethrow;
      }
    }
  }
}
