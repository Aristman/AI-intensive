import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import 'usecase.dart';

class SendMessageParams {
  final String message;
  final String model;
  final String systemPrompt;
  final String? jsonSchema;
  final List<MessageEntity>? history;

  const SendMessageParams({
    required this.message,
    required this.model,
    required this.systemPrompt,
    this.jsonSchema,
    this.history,
  });
}

class SendMessageUseCase implements UseCase<MessageEntity, SendMessageParams> {
  final ChatRepository repository;

  SendMessageUseCase(this.repository);

  @override
  Future<Either<Failure, MessageEntity>> call(SendMessageParams params) async {
    return await repository.sendMessage(
      message: params.message,
      model: params.model,
      systemPrompt: params.systemPrompt,
      jsonSchema: params.jsonSchema,
      history: params.history,
    );
  }
}
