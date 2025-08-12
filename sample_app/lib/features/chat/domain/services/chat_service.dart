import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../core/error/exceptions.dart';
import '../../../../core/enums/response_format.dart';
import '../../../../core/config/app_config.dart';

class ChatService {


  final AppConfig _appConfig = AppConfig();

  ChatService();

  Future<String> sendMessage({
    required String message,
    required String model,
    required String systemPrompt,
    required ResponseFormat responseFormat,
    String? jsonSchema,
  }) async {
    final apiKey = _appConfig.deepSeekApiKey;
    if (apiKey.isEmpty) {
      throw const ApiException('API key is not configured in .env file');
    }

    final uri = Uri.parse('${_appConfig.deepSeekBaseUrl}/v1/chat/completions');
    
    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            if (systemPrompt.isNotEmpty)
              {
                'role': 'system',
                'content': systemPrompt,
              },
            {
              'role': 'user',
              'content': message,
            },
          ],
          if (responseFormat == ResponseFormat.json)
            'response_format': {
              'type': 'json_object',
              if (jsonSchema != null) 'schema': jsonDecode(jsonSchema),
            },
          'temperature': 0.7,
          'max_tokens': 2000,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = responseData['choices'] as List?;
        
        if (choices != null && choices.isNotEmpty) {
          final content = choices.first['message']?['content'] as String?;
          if (content != null) {
            return content;
          }
        }
        
        throw const ApiException('Invalid response format from API');
      } else {
        final errorResponse = jsonDecode(response.body) as Map<String, dynamic>;
        final errorMessage = errorResponse['error']?['message'] as String?;
        throw ApiException(
          'API Error (${response.statusCode}): ${errorMessage ?? 'Unknown error'}',
        );
      }
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } on FormatException catch (e) {
      throw ApiException('Invalid response format: ${e.message}');
    } catch (e) {
      throw ApiException('Failed to send message: $e');
    }
  }
}
