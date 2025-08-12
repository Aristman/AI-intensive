// Requirements Agent Feature
// 
// Экспортирует все необходимые компоненты для работы с агентом сбора требований
export 'domain/entities/agent_state.dart' show AgentState;
export 'domain/repositories/agent_repository.dart';
export 'data/repositories/agent_repository_impl.dart';
export 'domain/usecases/process_user_input_use_case.dart';

// BLoC exports
export 'presentation/bloc/agent_bloc.dart';
export 'presentation/bloc/agent_event.dart';
// Note: agent_state.dart is not exported here to avoid naming conflicts
// Import it directly in files where needed with a prefix:
// import 'package:sample_app/features/requirements_agent/presentation/bloc/agent_state.dart' as bloc_state;

export 'presentation/pages/requirements_agent_screen.dart';
