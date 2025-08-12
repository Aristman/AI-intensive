import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:sample_app/core/error/exceptions.dart';
import 'package:sample_app/core/error/failures.dart' as failures;
import 'package:sample_app/core/network/network_info.dart';
import 'package:sample_app/features/chat/domain/repositories/chat_repository.dart';
import 'package:sample_app/features/requirements_agent/domain/entities/agent_state.dart';
import 'package:sample_app/features/requirements_agent/domain/repositories/agent_repository.dart';

class AgentRepositoryImpl implements AgentRepository {
  final ChatRepository chatRepository;
  final NetworkInfo networkInfo;

  const AgentRepositoryImpl({
    required this.chatRepository,
    required this.networkInfo,
  });

  @override
  Future<Either<failures.Failure, AgentState>> processUserInput({
    required String userInput,
    required AgentState currentState,
  }) async {
    if (!await networkInfo.isConnected) {
      return const Left(failures.NetworkFailure());
    }

    try {
      // Проверяем лимиты
      if (currentState.hasReachedMaxQuestions) {
        return Left(failures.AgentFailure('Достигнуто максимальное количество вопросов'));
      }

      if (currentState.hasReachedMaxFailedAttempts) {
        return Left(failures.AgentFailure('Слишком много неудачных попыток'));
      }

      // Формируем системный промпт
      final systemPrompt = _buildSystemPrompt(currentState);
      
      // Отправляем запрос в чат
      final result = await chatRepository.sendMessage(
        message: userInput,
        systemPrompt: systemPrompt,
        // Остальные параметры из настроек пользователя
        model: 'deepseek-chat',
      );

      return result.fold(
        (failure) => Left(failure),
        (message) {
          try {
            // Парсим ответ от модели
            final response = jsonDecode(message.content) as Map<String, dynamic>;
            
            // Обрабатываем ответ в зависимости от типа
            if (response['response_type'] == 'final_result') {
              final result = response['content'] as Map<String, dynamic>;
              return Right(
                currentState.copyWith(
                  result: result,
                  isCompleted: true,
                  questionCount: currentState.questionCount + 1,
                ),
              );
            } else if (response['response_type'] == 'questions') {
              final questions = List<String>.from(response['content']);
              return Right(
                currentState.copyWith(
                  questions: questions,
                  questionCount: currentState.questionCount + 1,
                ),
              );
            } else {
              return Left(failures.AgentFailure('Некорректный формат ответа от модели'));
            }
          } catch (e) {
            return Left(failures.ParsingFailure('Ошибка обработки ответа: $e'));
          }
        },
      );
    } on ServerException {
      return Left(failures.ServerFailure('Server error'));
    } catch (e) {
      return Left(failures.AgentFailure('Ошибка при обработке запроса: $e'));
    }
  }

  @override
  Future<Either<failures.Failure, AgentState>> resetAgent() async {
    return Right(AgentState.initial());
  }

  @override
  Future<Either<failures.Failure, void>> saveState(AgentState state) async {
    // TODO: Реализовать сохранение состояния
    return const Right(null);
  }

  @override
  Future<Either<failures.Failure, AgentState?>> loadState() async {
    // TODO: Реализовать загрузку состояния
    return const Right(null);
  }

  String _buildSystemPrompt(AgentState state) {
    return '''
    Ты — агент для сбора ТЗ Flutter-приложений. Следуй строгим правилам:

    1. Собери информацию по структуре:
    {
      "project_name": "",
      "core_functionality": [],
      "target_platforms": [],
      "design_requirements": "",
      "backend_integration": [],
      "deadline": "",
      "special_requirements": ""
    }

    2. Перед ответом всегда рассчитывай Uncertainty по формуле:
       Uncertainty = (количество_пустых_полей) / 7
       • Поле считается пустым, если confidence < 0.8
       • Confidence = 1.0 при наличии конкретных данных

    3. Если Uncertainty > 0.1:
       • Задай 1-3 уточняющих вопроса
       • Никогда не показывай JSON
       • Формат ответа: {"response_type": "questions", "content": ["Вопрос 1", "Вопрос 2"]}

    4. Если Uncertainty ≤ 0.1:
       • Выведи ТОЛЬКО готовый JSON
       • Формат ответа: {"response_type": "final_result", "content": { ... }}

    Дополнительные правила:
    1. Максимум 10 вопросов за сессию
    2. Если пользователь 3 раза не отвечает на вопрос - заверши диалог
    3. Никогда не обсуждай внутреннюю логику uncertainty
    4. Запрещено изменять структуру JSON
    ''';
  }
}
