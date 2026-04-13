import 'ingredient.dart';
import 'recipe_step.dart';

class Recipe {
  final String id;
  final String? videoUrl;
  final String canonicalUrl;
  final String title;
  final String creatorName;
  final String? thumbnailUrl;
  final int cookingTimeMinutes;
  final int portionSize;
  final bool isPlatformRecipe;
  final String? createdBy;
  final DateTime createdAt;
  final List<Ingredient> ingredients;
  final List<String> preparations;
  final List<RecipeStep> steps;
  final String? category;
  final String? region;

  const Recipe({
    required this.id,
    this.videoUrl,
    required this.canonicalUrl,
    required this.title,
    required this.creatorName,
    this.thumbnailUrl,
    required this.cookingTimeMinutes,
    this.portionSize = 2,
    this.isPlatformRecipe = false,
    this.createdBy,
    required this.createdAt,
    this.ingredients = const [],
    this.preparations = const [],
    this.steps = const [],
    this.category,
    this.region,
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String,
      videoUrl: json['video_url'] as String?,
      canonicalUrl: json['canonical_url'] as String,
      title: json['title'] as String,
      creatorName: json['creator_name'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      cookingTimeMinutes: json['cooking_time_minutes'] as int,
      portionSize: (json['portion_size'] as int?) ?? 2,
      isPlatformRecipe: (json['is_platform_recipe'] as bool?) ?? false,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      ingredients: (json['ingredients'] as List<dynamic>?)
              ?.map((e) => Ingredient.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      preparations: (json['preparations'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      steps: (json['steps'] as List<dynamic>?)
              ?.map((e) => RecipeStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      category: json['category'] as String?,
      region: json['region'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (videoUrl != null) 'video_url': videoUrl,
      'canonical_url': canonicalUrl,
      'title': title,
      'creator_name': creatorName,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      'cooking_time_minutes': cookingTimeMinutes,
      'portion_size': portionSize,
      'is_platform_recipe': isPlatformRecipe,
      if (createdBy != null) 'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'ingredients': ingredients.map((e) => e.toJson()).toList(),
      'preparations': preparations,
      'steps': steps.map((e) => e.toJson()).toList(),
      if (category != null) 'category': category,
      if (region != null) 'region': region,
    };
  }

  Recipe copyWith({
    String? id,
    String? videoUrl,
    String? canonicalUrl,
    String? title,
    String? creatorName,
    String? thumbnailUrl,
    int? cookingTimeMinutes,
    int? portionSize,
    bool? isPlatformRecipe,
    String? createdBy,
    DateTime? createdAt,
    List<Ingredient>? ingredients,
    List<String>? preparations,
    List<RecipeStep>? steps,
    String? category,
    String? region,
  }) {
    return Recipe(
      id: id ?? this.id,
      videoUrl: videoUrl ?? this.videoUrl,
      canonicalUrl: canonicalUrl ?? this.canonicalUrl,
      title: title ?? this.title,
      creatorName: creatorName ?? this.creatorName,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      cookingTimeMinutes: cookingTimeMinutes ?? this.cookingTimeMinutes,
      portionSize: portionSize ?? this.portionSize,
      isPlatformRecipe: isPlatformRecipe ?? this.isPlatformRecipe,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      ingredients: ingredients ?? this.ingredients,
      preparations: preparations ?? this.preparations,
      steps: steps ?? this.steps,
      category: category ?? this.category,
      region: region ?? this.region,
    );
  }
}
