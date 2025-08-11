import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecase/no_params.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import 'usecase.dart';

class GetChatHistoryUseCase implements UseCase<List<MessageEntity>, NoParams> {
  final ChatRepository repository;

  GetChatHistoryUseCase(this.repository);

  @override
  Future<Either<Failure, List<MessageEntity>>> call(NoParams params) async {
    return await repository.getChatHistory();
  }
}
