import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/message_entity.dart';

abstract class ChatRepository {
  // Отправка сообщения и получение ответа
  Future<Either<Failure, MessageEntity>> sendMessage({
    required String message,
    required String model,
    required String systemPrompt,
    String? jsonSchema,
    List<MessageEntity>? history,
  });
  
  // Получение истории сообщений
  Future<Either<Failure, List<MessageEntity>>> getChatHistory();
  
  // Сохранение сообщения в историю
  Future<Either<Failure, void>> saveMessage(MessageEntity message);
  
  // Очистка истории
  Future<Either<Failure, void>> clearHistory();
}
