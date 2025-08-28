import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telegram_summarizer/data/llm/yandex_gpt_usecase.dart';

void main() {
  test('YandexGptUseCase returns text on success', () async {
    final mock = MockClient((request) async {
      expect(request.url.toString(),
          'https://llm.api.cloud.yandex.net/foundationModels/v1/completion');
      expect(request.headers['Content-Type']!.startsWith('application/json'), isTrue);
      expect(request.headers['Authorization'], 'Api-Key api');
      expect(request.headers['x-folder-id'], 'folder');

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['modelUri'], 'gpt://folder/yandexgpt-lite');
      expect(body['messages'], isA<List>());

      return http.Response(
        jsonEncode({
          'result': {
            'alternatives': [
              {
                'message': {
                  'role': 'assistant',
                  'text': 'Hello!'
                }
              }
            ]
          }
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final usecase = YandexGptUseCase();
    final text = await usecase.complete(
      messages: const [
        {'role': 'user', 'content': 'Hi'}
      ],
      modelUri: 'yandexgpt-lite',
      iamToken: '',
      apiKey: 'api',
      folderId: 'folder',
      client: mock,
    );

    expect(text, 'Hello!');
  });

  test('YandexGptUseCase throws on non-200', () async {
    final mock = MockClient((request) async => http.Response('fail', 500));
    final usecase = YandexGptUseCase();

    expect(
      () => usecase.complete(
        messages: const [
          {'role': 'user', 'content': 'Hi'}
        ],
        modelUri: 'yandexgpt',
        iamToken: '',
        apiKey: 'api',
        folderId: 'folder',
        client: mock,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('YandexGptUseCase requires creds and folderId', () async {
    final mock = MockClient((request) async => http.Response('ok', 200));
    final usecase = YandexGptUseCase();

    // Missing creds
    expect(
      () => usecase.complete(
        messages: const [],
        modelUri: 'yandexgpt',
        iamToken: '',
        apiKey: '',
        folderId: 'folder',
        client: mock,
      ),
      throwsA(isA<Exception>()),
    );

    // Missing folder
    expect(
      () => usecase.complete(
        messages: const [],
        modelUri: 'yandexgpt',
        iamToken: 'iam',
        apiKey: '',
        folderId: '',
        client: mock,
      ),
      throwsA(isA<Exception>()),
    );
  });
}
