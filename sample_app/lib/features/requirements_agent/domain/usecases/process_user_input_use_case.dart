import 'package:dartz/dartz.dart';
import 'package:sample_app/core/error/failures.dart';
import 'package:sample_app/features/requirements_agent/domain/entities/agent_state.dart';
import 'package:sample_app/features/requirements_agent/domain/repositories/agent_repository.dart';
import '../../../chat/domain/usecases/usecase.dart';

class ProcessUserInputUseCase implements UseCase<AgentState, ProcessUserInputParams> {
  final AgentRepository repository;

  const ProcessUserInputUseCase(this.repository);

  @override
  Future<Either<Failure, AgentState>> call(ProcessUserInputParams params) async {
    return await repository.processUserInput(
      userInput: params.userInput,
      currentState: params.currentState,
    );
  }
}

class ProcessUserInputParams {
  final String userInput;
  final AgentState currentState;

  const ProcessUserInputParams({
    required this.userInput,
    required this.currentState,
  });
}
