import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sample_app/core/error/failures.dart';
import 'package:sample_app/features/requirements_agent/domain/entities/agent_state.dart' as agent_entity;
import 'package:sample_app/features/requirements_agent/domain/usecases/process_user_input_use_case.dart';
import 'package:sample_app/features/requirements_agent/presentation/bloc/agent_event.dart';
import 'package:sample_app/features/requirements_agent/presentation/bloc/agent_state.dart'
    as presentation;

class AgentBloc extends Bloc<AgentEvent, presentation.AgentState> {
  final ProcessUserInputUseCase processUserInput;
  
  AgentBloc({
    required this.processUserInput,
  }) : super(const presentation.AgentInitial()) {
    on<AgentInitialize>(_onInitialize);
    on<AgentProcessInput>(_onProcessInput);
    on<AgentReset>(_onReset);
  }

  FutureOr<void> _onInitialize(
    AgentInitialize event,
    Emitter<presentation.AgentState> emit,
  ) async {
    try {
      // Здесь можно загрузить сохраненное состояние
      emit(const presentation.AgentLoading());
      final initialState = agent_entity.AgentState.initial();
      
      // Сброс счетчиков при инициализации
      final resetState = initialState.copyWith(
        questionCount: 0,
        failedAttempts: 0,
      );
      
      emit(presentation.AgentQuestion(resetState));
    } catch (e) {
      emit(presentation.AgentError('Ошибка инициализации агента: $e'));
    }
  }

  FutureOr<void> _onProcessInput(
    AgentProcessInput event,
    Emitter<presentation.AgentState> emit,
  ) async {
    final currentState = state.agentState;
    if (currentState == null) {
      emit(const presentation.AgentError('Агент не инициализирован'));
      return;
    }

    // Check if we've reached the maximum number of questions
    if (currentState.hasReachedMaxQuestions) {
      emit(presentation.AgentError(
        'Достигнуто максимальное количество вопросов (${agent_entity.AgentState.maxQuestions}). Пожалуйста, завершите сбор требований.',
      ));
      return;
    }

    // Check if we've reached the maximum number of failed attempts
    if (currentState.hasReachedMaxFailedAttempts) {
      emit(presentation.AgentError(
        'Превышено максимальное количество попыток (${agent_entity.AgentState.maxFailedAttempts}). Пожалуйста, начните заново.',
      ));
      return;
    }

    emit(presentation.AgentLoading());

    final result = await processUserInput(
      ProcessUserInputParams(
        userInput: event.userInput,
        currentState: currentState,
      ),
    );

    result.fold(
      (failure) {
        // Increment failed attempts on failure
        final updatedState = currentState.copyWith(
          failedAttempts: currentState.failedAttempts + 1,
        );
        
        if (updatedState.hasReachedMaxFailedAttempts) {
          emit(presentation.AgentError(
            'Превышено максимальное количество попыток (${agent_entity.AgentState.maxFailedAttempts}). Пожалуйста, начните заново.',
            agentState: updatedState,
          ));
        } else {
          emit(presentation.AgentError(
            '${_mapFailureToMessage(failure)} (Попытка ${updatedState.failedAttempts + 1} из ${agent_entity.AgentState.maxFailedAttempts})',
            agentState: updatedState,
          ));
        }
      },
      (newState) {
        // Increment question count when we get a successful response with new questions
        final updatedState = newState.questions.isNotEmpty && 
                           (currentState.questions.isEmpty || 
                            newState.questions.first != currentState.questions.first)
            ? newState.copyWith(questionCount: currentState.questionCount + 1)
            : newState;

        if (updatedState.isCompleted) {
          emit(presentation.AgentCompleted(updatedState));
        } else if (updatedState.questions.isNotEmpty) {
          // Check if we've reached the maximum number of questions
          if (updatedState.hasReachedMaxQuestions) {
            emit(presentation.AgentError(
              'Достигнуто максимальное количество вопросов (${agent_entity.AgentState.maxQuestions}). Пожалуйста, завершите сбор требований.',
              agentState: updatedState,
            ));
          } else {
            emit(presentation.AgentQuestion(updatedState));
          }
        } else {
          emit(presentation.AgentReady(updatedState));
        }
      },
    );
  }

  FutureOr<void> _onReset(
    AgentReset event,
    Emitter<presentation.AgentState> emit,
  ) async {
    emit(const presentation.AgentLoading());
    final initialState = agent_entity.AgentState.initial();
    emit(presentation.AgentQuestion(initialState));
  }

  String _mapFailureToMessage(Failure failure) {
    if (failure is ServerFailure) {
      return 'Ошибка сервера';
    } else if (failure is NetworkFailure) {
      return 'Нет подключения к интернету';
    } else if (failure is ParsingFailure) {
      return 'Ошибка обработки данных: ${failure.message}';
    } else if (failure is CacheFailure) {
      return 'Ошибка кэширования';
    } else if (failure is AgentFailure) {
      return 'Ошибка агента: ${failure.message}';
    } else {
      return 'Неизвестная ошибка';
    }
  }
}
