import 'dart:convert';
import 'dart:developer';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:sample_app/domain/llm_usecase.dart';
import 'package:sample_app/models/app_settings.dart';

class DeepSeekUseCase implements LlmUseCase {
  static const String _apiUrl = 'https://api.deepseek.com/chat/completions';

  String get _apiKey => dotenv.env['DEEPSEEK_API_KEY'] ?? '';

  @override
  Future<String> complete({
    required List<Map<String, String>> messages,
    required AppSettings settings,
  }) async {
    log('DeepSeekUseCase.complete: Начинаем обработку запроса', name: 'DeepSeekUseCase');

    if (_apiKey.isEmpty) {
      log('DeepSeekUseCase: Ошибка - API ключ не найден', name: 'DeepSeekUseCase');
      throw Exception('API ключ DeepSeek не найден. Проверьте assets/.env');
    }

    final double temperature = settings.deepseekTemperature.clamp(0.0, 2.0);
    final int maxTokens = settings.deepseekMaxTokens > 0 ? settings.deepseekMaxTokens : 1;

    log('DeepSeekUseCase: Параметры - temperature: $temperature, maxTokens: $maxTokens', name: 'DeepSeekUseCase');
    log('DeepSeekUseCase: Сообщений для обработки: ${messages.length}', name: 'DeepSeekUseCase');

    final requestBody = {
      'model': 'deepseek-chat',
      'messages': messages,
      'stream': false,
      'max_tokens': maxTokens,
      'temperature': temperature,
      // Не задаем response_format принудительно, чтобы позволить уточняющие вопросы
      'response_format': null,
    };

    log('DeepSeekUseCase: Отправляем запрос к $_apiUrl', name: 'DeepSeekUseCase');
    log('DeepSeekUseCase: Тело запроса: ${jsonEncode(requestBody)}', name: 'DeepSeekUseCase');

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode(requestBody),
    );

    log('DeepSeekUseCase: Получен ответ с кодом ${response.statusCode}', name: 'DeepSeekUseCase');

    if (response.statusCode != 200) {
      log('DeepSeekUseCase: Ошибка HTTP ${response.statusCode}: ${response.body}', name: 'DeepSeekUseCase');
      throw Exception('Ошибка DeepSeek: ${response.statusCode} ${response.body}');
    }

    log('DeepSeekUseCase: Успешный ответ, парсим JSON', name: 'DeepSeekUseCase');
    final Map<String, dynamic> data = jsonDecode(response.body);
    final content = data['choices']?[0]?['message']?['content'];

    if (content is String && content.isNotEmpty) {
      log('DeepSeekUseCase: Успешно извлечен контент длиной ${content.length} символов', name: 'DeepSeekUseCase');
      return content;
    }

    log('DeepSeekUseCase: Ошибка - пустой контент в ответе', name: 'DeepSeekUseCase');
    throw Exception('Пустой ответ от DeepSeek');
  }
}
