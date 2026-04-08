import 'step_ingredient.dart';

enum FlameLevel { low, medium, high }

extension FlameLevelX on FlameLevel {
  String toJson() {
    switch (this) {
      case FlameLevel.low:
        return 'low';
      case FlameLevel.medium:
        return 'medium';
      case FlameLevel.high:
        return 'high';
    }
  }

  static FlameLevel? fromJson(String? value) {
    switch (value) {
      case 'low':
        return FlameLevel.low;
      case 'medium':
        return FlameLevel.medium;
      case 'high':
        return FlameLevel.high;
      default:
        return null;
    }
  }
}

class RecipeStep {
  final int stepNumber;
  final String title;
  final String description;
  final int? timerSeconds;
  final FlameLevel? flameLevel;
  final bool isPrep;
  final List<StepIngredient> ingredients;

  const RecipeStep({
    required this.stepNumber,
    required this.title,
    required this.description,
    this.timerSeconds,
    this.flameLevel,
    required this.isPrep,
    this.ingredients = const [],
  });

  factory RecipeStep.fromJson(Map<String, dynamic> json) {
    return RecipeStep(
      stepNumber: json['step_number'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      timerSeconds: json['timer_seconds'] as int?,
      flameLevel: FlameLevelX.fromJson(json['flame_level'] as String?),
      isPrep: json['is_prep'] as bool,
      ingredients: (json['ingredients'] as List<dynamic>?)
              ?.map((e) => StepIngredient.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'step_number': stepNumber,
      'title': title,
      'description': description,
      if (timerSeconds != null) 'timer_seconds': timerSeconds,
      if (flameLevel != null) 'flame_level': flameLevel!.toJson(),
      'is_prep': isPrep,
      'ingredients': ingredients.map((e) => e.toJson()).toList(),
    };
  }
}
