import 'package:dartz/dartz.dart' show Either;
import 'package:sample_app/core/error/failures.dart' show Failure;
import 'package:sample_app/core/usecase/no_params.dart';
import 'package:sample_app/features/chat/domain/repositories/chat_repository.dart';
import 'package:sample_app/features/chat/domain/usecases/usecase.dart';

class ClearChatHistoryUseCase implements UseCase<void, NoParams> {
  final ChatRepository repository;

  ClearChatHistoryUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(NoParams params) async {
    return await repository.clearHistory();
  }
}
