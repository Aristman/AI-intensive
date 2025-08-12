import 'package:equatable/equatable.dart';
import 'package:sample_app/features/requirements_agent/domain/entities/agent_state.dart';

abstract class AgentEvent extends Equatable {
  const AgentEvent();

  @override
  List<Object?> get props => [];
}

class AgentInitialize extends AgentEvent {
  const AgentInitialize();
}

class AgentProcessInput extends AgentEvent {
  final String userInput;

  const AgentProcessInput(this.userInput);

  @override
  List<Object?> get props => [userInput];
}

class AgentReset extends AgentEvent {
  const AgentReset();
}

class AgentSaveState extends AgentEvent {
  final AgentState state;

  const AgentSaveState(this.state);

  @override
  List<Object?> get props => [state];
}

class AgentLoadState extends AgentEvent {
  const AgentLoadState();
}
