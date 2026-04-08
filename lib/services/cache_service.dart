import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/recipe.dart';
import '../models/recipe_state.dart';

class CacheService {
  CacheService._();
  static final instance = CacheService._();

  static const _recipesBox = 'recipes';
  static const _statesBox = 'recipe_states';
  static const _prefsBox = 'preferences';

  // ──────────────────────────────────────────────────────────
  // Init — open all boxes at app start.
  // ──────────────────────────────────────────────────────────

  Future<void> init() async {
    await Future.wait([
      Hive.openBox<String>(_recipesBox),
      Hive.openBox<String>(_statesBox),
      Hive.openBox<dynamic>(_prefsBox),
    ]);
  }

  // ──────────────────────────────────────────────────────────
  // Recipes
  // ──────────────────────────────────────────────────────────

  Future<void> cacheRecipe(Recipe recipe) async {
    final box = await Hive.openBox<String>(_recipesBox);
    await box.put(recipe.id, jsonEncode(recipe.toJson()));
  }

  Future<Recipe?> getCachedRecipe(String id) async {
    try {
      final box = await Hive.openBox<String>(_recipesBox);
      final raw = box.get(id);
      if (raw == null) return null;
      return Recipe.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────
  // Recipe states
  // ──────────────────────────────────────────────────────────

  Future<void> saveRecipeState(RecipeState state) async {
    final box = await Hive.openBox<String>(_statesBox);
    await box.put(state.recipeId, jsonEncode(state.toJson()));
  }

  Future<RecipeState?> getRecipeState(String recipeId) async {
    try {
      final box = await Hive.openBox<String>(_statesBox);
      final raw = box.get(recipeId);
      if (raw == null) return null;
      return RecipeState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearRecipeState(String recipeId) async {
    final box = await Hive.openBox<String>(_statesBox);
    await box.delete(recipeId);
  }

  /// Returns the first recipe state with [CookingStatus.inProgress], or null.
  Future<RecipeState?> getActiveRecipeState() async {
    try {
      final box = await Hive.openBox<String>(_statesBox);
      for (final raw in box.values) {
        try {
          final state =
              RecipeState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          if (state.overallStatus == CookingStatus.inProgress) return state;
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}
    return null;
  }

  // ──────────────────────────────────────────────────────────
  // Preferences
  // ──────────────────────────────────────────────────────────

  /// Stores [value] under [key]. Passing null deletes the key.
  Future<void> setPreference(String key, dynamic value) async {
    final box = await Hive.openBox<dynamic>(_prefsBox);
    if (value == null) {
      await box.delete(key);
    } else {
      await box.put(key, value);
    }
  }

  Future<dynamic> getPreference(String key) async {
    final box = await Hive.openBox<dynamic>(_prefsBox);
    return box.get(key);
  }

  // ──────────────────────────────────────────────────────────
  // Housekeeping
  // ──────────────────────────────────────────────────────────

  /// Wipes all cached data. Call on logout.
  Future<void> clearAll() async {
    final boxes = await Future.wait([
      Hive.openBox<String>(_recipesBox),
      Hive.openBox<String>(_statesBox),
      Hive.openBox<dynamic>(_prefsBox),
    ]);
    for (final box in boxes) {
      await box.clear();
    }
  }
}
