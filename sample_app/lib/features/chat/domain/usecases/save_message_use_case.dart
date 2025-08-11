import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import 'usecase.dart';

class SaveMessageUseCase implements UseCase<void, MessageEntity> {
  final ChatRepository repository;

  SaveMessageUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(MessageEntity message) async {
    return await repository.saveMessage(message);
  }
}
