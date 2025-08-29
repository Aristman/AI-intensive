import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:sample_app/data/llm/tinylama_usecase.dart';
import 'package:sample_app/models/app_settings.dart';

import 'tinylama_usecase_test.mocks.dart';

@GenerateMocks([http.Client])
void main() {
  late TinyLlamaUseCase usecase;
  late MockClient mockClient;
  late AppSettings testSettings;

  setUp(() {
    mockClient = MockClient();
    usecase = TinyLlamaUseCase();
    testSettings = const AppSettings(
      selectedNetwork: NeuralNetwork.tinylama,
      tinylamaEndpoint: 'http://test-server:8000/v1/chat/completions',
      tinylamaTemperature: 0.7,
      tinylamaMaxTokens: 2048,
    );
  });

  group('TinyLlamaUseCase', () {
    test('successfully processes OpenAI-compatible response', () async {
      // Arrange
      const testMessages = [
        {'role': 'user', 'content': 'Hello, how are you?'}
      ];

      final mockResponse = {
        'id': 'chatcmpl-test123',
        'object': 'chat.completion',
        'created': 1234567890,
        'model': 'TinyLlama-1.1B-Chat',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'Hello! I am doing well, thank you for asking.'
            },
            'finish_reason': 'stop'
          }
        ],
        'usage': {
          'prompt_tokens': 5,
          'completion_tokens': 10,
          'total_tokens': 15
        }
      };

      when(mockClient.post(
        any,
        headers: anyNamed('headers'),
        body: anyNamed('body'),
      )).thenAnswer((_) async => http.Response(
        mockResponse.toString(),
        200,
        headers: {'content-type': 'application/json'},
      ));

      // Act
      final result = await usecase.complete(
        messages: testMessages,
        settings: testSettings,
      );

      // Assert
      expect(result, 'Hello! I am doing well, thank you for asking.');
    });

    test('handles empty endpoint gracefully', () async {
      // Arrange
      const messages = [
        {'role': 'user', 'content': 'Test message'}
      ];

      const invalidSettings = AppSettings(
        selectedNetwork: NeuralNetwork.tinylama,
        tinylamaEndpoint: '', // Empty endpoint
        tinylamaTemperature: 0.7,
        tinylamaMaxTokens: 2048,
      );

      // Act & Assert
      expect(
        () => usecase.complete(messages: messages, settings: invalidSettings),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('TinyLlama endpoint не задан'),
        )),
      );
    });

    test('handles HTTP error responses', () async {
      // Arrange
      const testMessages = [
        {'role': 'user', 'content': 'Test message'}
      ];

      when(mockClient.post(
        any,
        headers: anyNamed('headers'),
        body: anyNamed('body'),
      )).thenAnswer((_) async => http.Response(
        'Internal Server Error',
        500,
      ));

      // Act & Assert
      expect(
        () => usecase.complete(messages: testMessages, settings: testSettings),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Ошибка TinyLlama API: 500'),
        )),
      );
    });

    test('handles malformed JSON response', () async {
      // Arrange
      const testMessages = [
        {'role': 'user', 'content': 'Test message'}
      ];

      when(mockClient.post(
        any,
        headers: anyNamed('headers'),
        body: anyNamed('body'),
      )).thenAnswer((_) async => http.Response(
        'Invalid JSON response',
        200,
        headers: {'content-type': 'application/json'},
      ));

      // Act & Assert
      expect(
        () => usecase.complete(messages: testMessages, settings: testSettings),
        throwsA(isA<Exception>()),
      );
    });

    test('handles response without choices', () async {
      // Arrange
      const testMessages = [
        {'role': 'user', 'content': 'Test message'}
      ];

      final mockResponse = {
        'id': 'chatcmpl-test123',
        'object': 'chat.completion',
        'created': 1234567890,
        'model': 'TinyLlama-1.1B-Chat',
        'choices': [], // Empty choices
        'usage': {
          'prompt_tokens': 5,
          'completion_tokens': 0,
          'total_tokens': 5
        }
      };

      when(mockClient.post(
        any,
        headers: anyNamed('headers'),
        body: anyNamed('body'),
      )).thenAnswer((_) async => http.Response(
        mockResponse.toString(),
        200,
        headers: {'content-type': 'application/json'},
      ));

      // Act & Assert
      expect(
        () => usecase.complete(messages: testMessages, settings: testSettings),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('отсутствуют choices'),
        )),
      );
    });

    test('handles response with empty content', () async {
      // Arrange
      const testMessages = [
        {'role': 'user', 'content': 'Test message'}
      ];

      final mockResponse = {
        'id': 'chatcmpl-test123',
        'object': 'chat.completion',
        'created': 1234567890,
        'model': 'TinyLlama-1.1B-Chat',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': '' // Empty content
            },
            'finish_reason': 'stop'
          }
        ],
        'usage': {
          'prompt_tokens': 5,
          'completion_tokens': 0,
          'total_tokens': 5
        }
      };

      when(mockClient.post(
        any,
        headers: anyNamed('headers'),
        body: anyNamed('body'),
      )).thenAnswer((_) async => http.Response(
        mockResponse.toString(),
        200,
        headers: {'content-type': 'application/json'},
      ));

      // Act & Assert
      expect(
        () => usecase.complete(messages: testMessages, settings: testSettings),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Пустой контент в ответе'),
        )),
      );
    });
  });
}
