import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:sample_app/features/chat/chat.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/network/api_service.dart';
import '../../domain/entities/message_entity.dart';
import '../models/deepseek/deepseek_message_model.dart';
import '../models/yandexgpt/yandex_message_model.dart';

class ChatRemoteDataSourceImpl implements ChatRemoteDataSource {
  final ApiService apiService;
  final Dio dio;
  final Logger logger;
  final String deepSeekApiKey;
  final String? yandexApiKey;
  final String? yandexFolderId;

  ChatRemoteDataSourceImpl({
    required this.apiService,
    required this.dio,
    required this.logger,
    required this.deepSeekApiKey,
    this.yandexApiKey,
    this.yandexFolderId,
  }) {
    // Configure Dio interceptors for logging
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        logger.d("""
          Request: ${options.method} ${options.uri}
          Headers: ${options.headers}
          Data: ${options.data}
        """);
        return handler.next(options);
      },
      onResponse: (response, handler) {
        logger.d("""
          Response: ${response.statusCode} ${response.statusMessage}
          Data: ${response.data}
        """);
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        logger.e("""
          Error: ${e.type}
          Message: ${e.message}
          Response: ${e.response?.data}
          Stack trace: ${e.stackTrace}
        """);
        return handler.next(e);
      },
    ));
  }

  @override
  Future<Either<Failure, String>> sendDeepSeekMessage({
    required String message,
    required String model,
    required String systemPrompt,
    String? jsonSchema,
    List<MessageEntity>? history,
  }) async {
    try {
      logger.d('Sending message to DeepSeek API');

      // Prepare messages for context
      final messages = <DeepSeekMessageModel>[
        DeepSeekMessageModel(
          role: 'system',
          content: systemPrompt,
        ),
        if (history != null)
          ...history
              .map((msg) => DeepSeekMessageModel(
                    role: msg.isUser ? 'user' : 'assistant',
                    content: msg.content,
                  ))
              .toList(),
        DeepSeekMessageModel(
          role: 'user',
          content: message,
        ),
      ];

      // Prepare request
      final request = DeepSeekRequestModel(
        model: model,
        messages: messages,
        responseFormat: jsonSchema != null
            ? {
                'type': 'json_object',
                'schema': jsonDecode(jsonSchema),
              }
            : null,
      );

      // Send request using Dio
      final response = await dio.post(
        '${apiService.baseUrl}/chat/completions',
        data: request.toJson(),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $deepSeekApiKey',
          },
        ),
      );

      // Process response
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map &&
            data.containsKey('choices') &&
            (data['choices'] as List).isNotEmpty) {
          final content = data['choices'][0]['message']['content'];
          if (content != null) {
            logger.d('Successfully received response from DeepSeek API');
            return Right(content.toString());
          }
        }
        return const Left(
            ServerFailure('Invalid response format from DeepSeek API'));
      } else {
        logger.w('DeepSeek API returned error: ${response.statusCode}');
        return Left(
          ServerFailure(
            'API request failed with status ${response.statusCode}',
            statusCode: response.statusCode,
          ),
        );
      }
    } on DioException catch (e) {
      logger.e('Dio error while calling DeepSeek API', error: e);
      return Left(
        ServerFailure(
          e.message ?? 'Network error occurred',
          statusCode: e.response?.statusCode,
        ),
      );
    } catch (e, stackTrace) {
      logger.e('Unexpected error in sendDeepSeekMessage',
          error: e, stackTrace: stackTrace);
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> sendYandexMessage({
    required String message,
    required String model,
    required String systemPrompt,
    String? jsonSchema,
    List<MessageEntity>? history,
  }) async {
    if (yandexApiKey == null || yandexFolderId == null) {
      logger.w('Yandex API credentials not configured');
      return const Left(ServerFailure('Yandex API credentials not configured'));
    }

    try {
      logger.d('Sending message to YandexGPT API');

      // Prepare messages for context
      final messages = <YandexMessageModel>[
        YandexMessageModel(
          role: 'system',
          text: systemPrompt,
        ),
        if (history != null)
          ...history
              .map((msg) => YandexMessageModel(
                    role: msg.isUser ? 'user' : 'assistant',
                    text: msg.content,
                  ))
              .toList(),
        YandexMessageModel(
          role: 'user',
          text: message,
        ),
      ];

      // Prepare request
      final request = YandexRequestModel(
        modelUri: 'gpt://$yandexFolderId/$model',
        messages: messages,
        completionOptions: YandexCompletionOptions(
          stream: false,
          temperature: 0.6,
          maxTokens: 2000,
        ),
      );

      // Get IAM token for Yandex Cloud
      final iamToken = await _getIamToken(yandexApiKey!);

      // Send request using Dio
      final response = await dio.post(
        'https://llm.api.cloud.yandex.net/foundationModels/v1/completion',
        data: request.toJson(),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $iamToken',
            'x-folder-id': yandexFolderId,
          },
        ),
      );

      // Process response
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map &&
            data.containsKey('result') &&
            data['result'] is Map &&
            data['result'].containsKey('alternatives') &&
            (data['result']['alternatives'] as List).isNotEmpty) {
          final content = data['result']['alternatives'][0]['message']['text'];
          if (content != null) {
            logger.d('Successfully received response from YandexGPT API');
            return Right(content.toString());
          }
        }
        return const Left(
            ServerFailure('Invalid response format from YandexGPT API'));
      } else {
        logger.w('YandexGPT API returned error: ${response.statusCode}');
        return Left(
          ServerFailure(
            'YandexGPT API request failed with status ${response.statusCode}',
            statusCode: response.statusCode,
          ),
        );
      }
    } on DioException catch (e) {
      logger.e('Dio error while calling YandexGPT API', error: e);
      return Left(
        ServerFailure(
          e.message ?? 'Network error occurred with YandexGPT API',
          statusCode: e.response?.statusCode,
        ),
      );
    } catch (e, stackTrace) {
      logger.e('Unexpected error in sendYandexMessage',
          error: e, stackTrace: stackTrace);
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }

  /// Fetches IAM token for Yandex Cloud authentication
  Future<String> _getIamToken(String apiKey) async {
    try {
      logger.d('Fetching IAM token from Yandex Cloud');

      final response = await dio.post(
        'https://iam.api.cloud.yandex.net/iam/v1/tokens',
        data: {
          'yandexPassportOauthToken': apiKey,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final token = response.data['iamToken'];
        if (token != null) {
          logger.d('Successfully obtained IAM token');
          return token.toString();
        }
      }

      logger.w('Failed to obtain IAM token: ${response.statusCode}');
      throw ServerException('Failed to authenticate with Yandex Cloud');
    } on DioException catch (e) {
      logger.e('Error obtaining IAM token', error: e);
      throw ServerException(
        e.message ?? 'Failed to authenticate with Yandex Cloud',
        statusCode: e.response?.statusCode,
      );
    } catch (e, stackTrace) {
      logger.e('Unexpected error in _getIamToken',
          error: e, stackTrace: stackTrace);
      throw ServerException('Failed to authenticate with Yandex Cloud');
    }
  }
}
