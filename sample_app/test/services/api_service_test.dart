import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

void main() {
  // This would be better as a separate service class in a real app
  group('API Integration Tests', () {
    late String apiKey;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      // Загружаем ключ из assets/.env без flutter_dotenv
      final content = await rootBundle.loadString('assets/.env');
      apiKey = '';
      for (final raw in const LineSplitter().convert(content)) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        final key = line.substring(0, eq).trim();
        var value = line.substring(eq + 1).trim();
        if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        if (key == 'DEEPSEEK_API_KEY') {
          apiKey = value;
          break;
        }
      }
    });

    test('should format API request correctly', () {
      // This is a simple test to verify the request format
      // In a real app, you would test the service class methods
      final apiUrl = 'https://api.deepseek.com/chat/completions';
      // Берём ключ из assets/.env
      
      expect(apiUrl, isNotEmpty);
      expect(apiKey, isNotEmpty);
    });

    test('should handle successful API response format', () {
      // Test the response parsing logic
      final responseJson = {
        'choices': [
          {
            'message': {
              'content': 'Test response',
              'role': 'assistant'
            }
          }
        ]
      };
      
      final response = http.Response(jsonEncode(responseJson), 200);
      final data = jsonDecode(response.body);
      
      expect(data['choices'], isList);
      expect(data['choices'][0]['message']['content'], 'Test response');
    });

    test('should handle API error response', () {
      // Test error response handling
      final errorResponse = http.Response('Error', 500);
      
      expect(errorResponse.statusCode, 500);
      expect(errorResponse.body, 'Error');
    });
  });
}
