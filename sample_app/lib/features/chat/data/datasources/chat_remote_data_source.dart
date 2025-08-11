import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/message_entity.dart';

abstract class ChatRemoteDataSource {
  // Для DeepSeek API
  Future<Either<Failure, String>> sendDeepSeekMessage({
    required String message,
    required String model,
    required String systemPrompt,
    String? jsonSchema,
    List<MessageEntity>? history,
  });

  // Для YandexGPT API
  Future<Either<Failure, String>> sendYandexMessage({
    required String message,
    required String model,
    required String systemPrompt,
    String? jsonSchema,
    List<MessageEntity>? history,
  });
}
