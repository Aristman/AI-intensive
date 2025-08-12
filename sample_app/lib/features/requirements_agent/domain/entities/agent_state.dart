import 'package:equatable/equatable.dart';

class AgentState extends Equatable {
  final Map<String, dynamic> progress;
  final double uncertainty;
  final List<String> questions;
  final bool isCompleted;
  final Map<String, dynamic>? result;
  final int questionCount;
  final int failedAttempts;
  static const int maxQuestions = 10;
  static const int maxFailedAttempts = 3;

  const AgentState({
    required this.progress,
    required this.uncertainty,
    required this.questions,
    this.isCompleted = false,
    this.result,
    this.questionCount = 0,
    this.failedAttempts = 0,
  });

  factory AgentState.initial() {
    return AgentState(
      progress: const {
        'project_name': {'value': '', 'confidence': 0.0},
        'core_functionality': {'value': <String>[], 'confidence': 0.0},
        'target_platforms': {'value': <String>[], 'confidence': 0.0},
        'design_requirements': {'value': '', 'confidence': 0.0},
        'backend_integration': {'value': <String>[], 'confidence': 0.0},
        'deadline': {'value': '', 'confidence': 0.0},
        'special_requirements': {'value': '', 'confidence': 0.0},
      },
      uncertainty: 1.0,
      questions: const [],
    );
  }

  AgentState copyWith({
    Map<String, dynamic>? progress,
    double? uncertainty,
    List<String>? questions,
    bool? isCompleted,
    Map<String, dynamic>? result,
    int? questionCount,
    int? failedAttempts,
  }) {
    return AgentState(
      progress: progress ?? this.progress,
      uncertainty: uncertainty ?? this.uncertainty,
      questions: questions ?? this.questions,
      isCompleted: isCompleted ?? this.isCompleted,
      result: result ?? this.result,
      questionCount: questionCount ?? this.questionCount,
      failedAttempts: failedAttempts ?? this.failedAttempts,
    );
  }

  bool get hasReachedMaxQuestions => questionCount >= maxQuestions;
  bool get hasReachedMaxFailedAttempts => failedAttempts >= maxFailedAttempts;

  @override
  List<Object?> get props => [
        progress,
        uncertainty,
        questions,
        isCompleted,
        result,
        questionCount,
        failedAttempts,
      ];
}
