import 'dart:convert';
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
    if (_apiKey.isEmpty) {
      throw Exception('API ключ DeepSeek не найден. Проверьте assets/.env');
    }

    final double temperature = settings.deepseekTemperature.clamp(0.0, 2.0);
    final int maxTokens = settings.deepseekMaxTokens > 0 ? settings.deepseekMaxTokens : 1;

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'messages': messages,
        'stream': false,
        'max_tokens': maxTokens,
        'temperature': temperature,
        // Не задаем response_format принудительно, чтобы позволить уточняющие вопросы
        'response_format': null,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка DeepSeek: ${response.statusCode} ${response.body}');
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    final content = data['choices']?[0]?['message']?['content'];
    if (content is String && content.isNotEmpty) {
      return content;
    }
    throw Exception('Пустой ответ от DeepSeek');
  }

  @override
  Future<LlmResponse> completeWithUsage({
    required List<Map<String, String>> messages,
    required AppSettings settings,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('API ключ DeepSeek не найден. Проверьте assets/.env');
    }

    final double temperature = settings.deepseekTemperature.clamp(0.0, 2.0);
    final int maxTokens = settings.deepseekMaxTokens > 0 ? settings.deepseekMaxTokens : 1;

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'messages': messages,
        'stream': false,
        'max_tokens': maxTokens,
        'temperature': temperature,
        // Не задаем response_format принудительно, чтобы позволить уточняющие вопросы
        'response_format': null,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка DeepSeek: ${response.statusCode} ${response.body}');
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    final content = data['choices']?[0]?['message']?['content'];
    final usage = data['usage'];

    Map<String, int>? tokenUsage;
    if (usage is Map<String, dynamic>) {
      tokenUsage = {
        'inputTokens': usage['prompt_tokens'] as int? ?? 0,
        'completionTokens': usage['completion_tokens'] as int? ?? 0,
        'totalTokens': usage['total_tokens'] as int? ?? 0,
      };
    }

    if (content is String && content.isNotEmpty) {
      return LlmResponse(text: content, usage: tokenUsage);
    }
    throw Exception('Пустой ответ от DeepSeek');
  }
}
