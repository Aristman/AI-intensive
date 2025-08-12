import 'package:dartz/dartz.dart';
import 'package:sample_app/core/error/failures.dart';
import 'package:sample_app/features/requirements_agent/domain/entities/agent_state.dart';

abstract class AgentRepository {
  /// Обрабатывает пользовательский ввод и возвращает обновленное состояние агента
  Future<Either<Failure, AgentState>> processUserInput({
    required String userInput,
    required AgentState currentState,
  });

  /// Сбрасывает состояние агента к начальному
  Future<Either<Failure, AgentState>> resetAgent();

  /// Сохраняет текущее состояние агента
  Future<Either<Failure, void>> saveState(AgentState state);

  /// Загружает сохраненное состояние агента
  Future<Either<Failure, AgentState?>> loadState();
}
