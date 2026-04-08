enum CookingStatus { notStarted, inProgress, paused, completed }

extension CookingStatusX on CookingStatus {
  String toJson() {
    switch (this) {
      case CookingStatus.notStarted:
        return 'not_started';
      case CookingStatus.inProgress:
        return 'in_progress';
      case CookingStatus.paused:
        return 'paused';
      case CookingStatus.completed:
        return 'completed';
    }
  }

  static CookingStatus fromJson(String value) {
    switch (value) {
      case 'in_progress':
        return CookingStatus.inProgress;
      case 'paused':
        return CookingStatus.paused;
      case 'completed':
        return CookingStatus.completed;
      default:
        return CookingStatus.notStarted;
    }
  }
}

enum StepStatus { notStarted, active, completed, skipped }

extension StepStatusX on StepStatus {
  String toJson() {
    switch (this) {
      case StepStatus.notStarted:
        return 'not_started';
      case StepStatus.active:
        return 'active';
      case StepStatus.completed:
        return 'completed';
      case StepStatus.skipped:
        return 'skipped';
    }
  }

  static StepStatus fromJson(String value) {
    switch (value) {
      case 'active':
        return StepStatus.active;
      case 'completed':
        return StepStatus.completed;
      case 'skipped':
        return StepStatus.skipped;
      default:
        return StepStatus.notStarted;
    }
  }
}

class RecipeState {
  final String recipeId;
  final CookingStatus overallStatus;
  final Map<int, StepStatus> stepStates;
  final int currentStepIndex;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const RecipeState({
    required this.recipeId,
    this.overallStatus = CookingStatus.notStarted,
    this.stepStates = const {},
    this.currentStepIndex = 0,
    this.startedAt,
    this.completedAt,
  });

  factory RecipeState.initial(String recipeId) {
    return RecipeState(recipeId: recipeId);
  }

  factory RecipeState.fromJson(Map<String, dynamic> json) {
    final rawStepStates =
        (json['step_states'] as Map<String, dynamic>?) ?? {};

    return RecipeState(
      recipeId: json['recipe_id'] as String,
      overallStatus:
          CookingStatusX.fromJson(json['overall_status'] as String),
      stepStates: rawStepStates.map(
        (key, value) => MapEntry(
          int.parse(key),
          StepStatusX.fromJson(value as String),
        ),
      ),
      currentStepIndex: (json['current_step_index'] as int?) ?? 0,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'recipe_id': recipeId,
      'overall_status': overallStatus.toJson(),
      'step_states': stepStates.map(
        (key, value) => MapEntry(key.toString(), value.toJson()),
      ),
      'current_step_index': currentStepIndex,
      if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
    };
  }

  RecipeState copyWith({
    String? recipeId,
    CookingStatus? overallStatus,
    Map<int, StepStatus>? stepStates,
    int? currentStepIndex,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return RecipeState(
      recipeId: recipeId ?? this.recipeId,
      overallStatus: overallStatus ?? this.overallStatus,
      stepStates: stepStates ?? this.stepStates,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
