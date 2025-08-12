import 'package:equatable/equatable.dart';
import 'package:sample_app/features/requirements_agent/domain/entities/agent_state.dart' as agent_entity;

abstract class AgentState extends Equatable {
  final agent_entity.AgentState? agentState;
  final String? error;

  const AgentState({this.agentState, this.error});

  @override
  List<Object?> get props => [agentState, error];
}

class AgentInitial extends AgentState {
  const AgentInitial();
}

class AgentLoading extends AgentState {
  const AgentLoading();
}

class AgentReady extends AgentState {
  const AgentReady(agent_entity.AgentState state) : super(agentState: state);
}

class AgentQuestion extends AgentState {
  const AgentQuestion(agent_entity.AgentState state) : super(agentState: state);
}

class AgentCompleted extends AgentState {
  const AgentCompleted(agent_entity.AgentState state) : super(agentState: state);
}

class AgentError extends AgentState {
  const AgentError(
    String message, {
    agent_entity.AgentState? agentState,
  }) : super(
          error: message,
          agentState: agentState,
        );
}
