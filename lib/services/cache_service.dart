import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/recipe.dart';
import '../models/recipe_state.dart';

class CacheService {
  CacheService._();
  static final instance = CacheService._();

  static const _recipesBox = 'recipes';
  static const _statesBox = 'recipe_states';
  static const _prefsBox = 'preferences';
  static const _hiveTimeout = Duration(seconds: 5);

  void _log(String msg) {
    if (kDebugMode) debugPrint('[CacheService] $msg');
  }

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
    final box = await Hive.openBox<String>(_recipesBox)
        .timeout(_hiveTimeout);
    await box.put(recipe.id, jsonEncode(recipe.toJson()));
    _log('Cached recipe ${recipe.id} ("${recipe.title}")');
  }

  Future<Recipe?> getCachedRecipe(String id) async {
    try {
      final box = await Hive.openBox<String>(_recipesBox)
          .timeout(_hiveTimeout);
      final raw = box.get(id);
      if (raw == null) return null;
      return Recipe.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on TimeoutException {
      _log('Timeout reading recipe $id from cache');
      return null;
    } on FormatException catch (e) {
      _log('Corrupted cache entry for recipe $id: $e — clearing');
      final box = await Hive.openBox<String>(_recipesBox);
      await box.delete(id);
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────
  // Recipe states
  // ──────────────────────────────────────────────────────────

  Future<void> saveRecipeState(RecipeState state) async {
    final box = await Hive.openBox<String>(_statesBox)
        .timeout(_hiveTimeout);
    await box.put(state.recipeId, jsonEncode(state.toJson()));
    _log('Saved state for recipe ${state.recipeId}');
  }

  Future<RecipeState?> getRecipeState(String recipeId) async {
    try {
      final box = await Hive.openBox<String>(_statesBox)
          .timeout(_hiveTimeout);
      final raw = box.get(recipeId);
      if (raw == null) return null;
      return RecipeState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on TimeoutException {
      _log('Timeout reading state for recipe $recipeId');
      return null;
    } on FormatException catch (e) {
      _log('Corrupted state cache for recipe $recipeId: $e — clearing');
      final box = await Hive.openBox<String>(_statesBox);
      await box.delete(recipeId);
      return null;
    }
  }

  Future<void> clearRecipeState(String recipeId) async {
    final box = await Hive.openBox<String>(_statesBox)
        .timeout(_hiveTimeout);
    await box.delete(recipeId);
  }

  /// Returns the first recipe state with [CookingStatus.inProgress], or null.
  Future<RecipeState?> getActiveRecipeState() async {
    try {
      final box = await Hive.openBox<String>(_statesBox)
          .timeout(_hiveTimeout);
      for (final raw in box.values) {
        try {
          final state =
              RecipeState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          if (state.overallStatus == CookingStatus.inProgress) return state;
        } on FormatException catch (e) {
          _log('Skipping corrupted state entry: $e');
        }
      }
    } on TimeoutException {
      _log('Timeout scanning active recipe states');
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────
  // Preferences
  // ──────────────────────────────────────────────────────────

  /// Stores [value] under [key]. Passing null deletes the key.
  Future<void> setPreference(String key, dynamic value) async {
    final box = await Hive.openBox<dynamic>(_prefsBox)
        .timeout(_hiveTimeout);
    if (value == null) {
      await box.delete(key);
    } else {
      await box.put(key, value);
    }
  }

  Future<dynamic> getPreference(String key) async {
    try {
      final box = await Hive.openBox<dynamic>(_prefsBox)
          .timeout(_hiveTimeout);
      return box.get(key);
    } on TimeoutException {
      _log('Timeout reading preference $key');
      return null;
    }
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
    _log('All caches cleared');
  }
}
