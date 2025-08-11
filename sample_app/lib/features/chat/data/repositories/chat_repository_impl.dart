import 'package:dartz/dartz.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_data_source.dart';
import '../datasources/chat_local_data_source.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ChatRemoteDataSource remoteDataSource;
  final ChatLocalDataSource localDataSource;

  ChatRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<Either<Failure, MessageEntity>> sendMessage({
    required String message,
    required String model,
    required String systemPrompt,
    String? jsonSchema,
    List<MessageEntity>? history,
  }) async {
    try {
      // Сохраняем сообщение пользователя в историю
      final userMessage = MessageEntity(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: message,
        isUser: true,
      );
      
      await localDataSource.saveMessage(userMessage);

      // Отправляем сообщение в соответствующее API
      final Either<Failure, String> response;
      
      if (model.toLowerCase().contains('yandex')) {
        response = await remoteDataSource.sendYandexMessage(
          message: message,
          model: model,
          systemPrompt: systemPrompt,
          jsonSchema: jsonSchema,
          history: history,
        );
      } else {
        // По умолчанию используем DeepSeek
        response = await remoteDataSource.sendDeepSeekMessage(
          message: message,
          model: model,
          systemPrompt: systemPrompt,
          jsonSchema: jsonSchema,
          history: history,
        );
      }

      return response.fold(
        (failure) => Left(failure),
        (responseText) async {
          // Сохраняем ответ бота в историю
          final botMessage = MessageEntity(
            id: '${DateTime.now().millisecondsSinceEpoch}_bot',
            content: responseText,
            isUser: false,
            metadata: {
              'model': model,
              'timestamp': DateTime.now().toIso8601String(),
            },
          );
          
          await localDataSource.saveMessage(botMessage);
          return Right(botMessage);
        },
      );
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    } on CacheException {
      return const Left(CacheFailure('Failed to save message to local storage'));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<MessageEntity>>> getChatHistory() async {
    try {
      final messages = await localDataSource.getMessages();
      return Right(messages);
    } on CacheException {
      return const Left(CacheFailure('Failed to load chat history'));
    } catch (e) {
      return Left(CacheFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> saveMessage(MessageEntity message) async {
    try {
      await localDataSource.saveMessage(message);
      return Right<Failure, void>(null);
    } on CacheException {
      return Left<Failure, void>(CacheFailure('Failed to save message'));
    } catch (e) {
      return Left<Failure, void>(CacheFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> clearHistory() async {
    try {
      await localDataSource.clearMessages();
      return Right<Failure, void>(null);
    } on CacheException {
      return Left<Failure, void>(CacheFailure('Failed to clear history'));
    } catch (e) {
      return Left<Failure, void>(CacheFailure('Unexpected error: $e'));
    }
  }
}
