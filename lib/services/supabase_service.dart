import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../models/recipe.dart';
import '../models/user_profile.dart';
import 'app_exception.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;

  void _log(String msg) {
    if (kDebugMode) debugPrint('[SupabaseService] $msg');
  }

  // ──────────────────────────────────────────────────────────
  // AUTH
  // ──────────────────────────────────────────────────────────

  Future<void> signInWithOtp(String email) async {
    _log('Sending OTP to $email');
    try {
      await _client.auth.signInWithOtp(email: email, shouldCreateUser: true);
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      throw AppException(
        'Failed to send OTP. Please try again.',
        code: 'otp_send_failed',
      );
    }
  }

  Future<AuthResponse> verifyOtp(String email, String otp) async {
    _log('Verifying OTP for $email');
    try {
      final response = await _client.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.email,
      );
      return response;
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      throw AppException(
        'OTP verification failed. Please try again.',
        code: 'otp_verify_failed',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      throw AppException(
        'Sign out failed. Please try again.',
        code: 'signout_failed',
      );
    }
  }

  User? getCurrentUser() => _client.auth.currentUser;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  // ──────────────────────────────────────────────────────────
  // PROFILE
  // ──────────────────────────────────────────────────────────

  Future<UserProfile> getProfile() async {
    final uid = _requireUid();
    final email = _client.auth.currentUser?.email ?? '';
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      // New user — no profile row yet. Return a stub.
      if (data == null) {
        return UserProfile(
          id: uid,
          email: email,
          name: '',
          foodPreference: FoodPreference.everything,
          createdAt: DateTime.now(),
        );
      }
      return UserProfile.fromJson(data);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not load your profile. Please try again.',
        code: 'profile_fetch_failed',
      );
    }
  }

  Future<void> updateProfile({
    String? name,
    FoodPreference? foodPreference,
    String? phone,
    String? avatarUrl,
  }) async {
    final uid = _requireUid();

    final email = _client.auth.currentUser?.email ?? '';

    final updates = <String, dynamic>{
      'id': uid,
      'email': email,
      'name': ?name,
      if (foodPreference != null) 'food_preference': foodPreference.toJson(),
      'phone': ?phone,
      'avatar_url': ?avatarUrl,
    };

    try {
      _log('Upserting profile for $uid: $updates');
      await _client.from('profiles').upsert(updates);
      _log('Profile upsert succeeded');
    } on PostgrestException catch (e) {
      _log('Profile upsert failed (PostgrestException): code=${e.code} message=${e.message} details=${e.details}');
      throw _mapPostgrestException(e);
    } catch (e) {
      _log('Profile upsert failed (unknown): $e');
      throw AppException(
        'Could not update your profile. Please try again.',
        code: 'profile_update_failed',
      );
    }
  }

  Future<bool> isProfileComplete() async {
    final uid = _requireUid();
    try {
      final data = await _client
          .from('profiles')
          .select('name, food_preference')
          .eq('id', uid)
          .maybeSingle();
      // No profile row yet — new user, profile not complete.
      if (data == null) return false;
      return data['name'] != null && data['food_preference'] != null;
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not check profile status.',
        code: 'profile_check_failed',
      );
    }
  }

  // ──────────────────────────────────────────────────────────
  // RECIPES
  // ──────────────────────────────────────────────────────────

  Future<Recipe?> getRecipeById(String id) async {
    try {
      final data = await _client
          .from('recipes')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (data == null) return null;
      return Recipe.fromJson(data);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw const AppException(
        'Could not load the recipe. Please try again.',
        code: 'recipe_fetch_failed',
      );
    }
  }

  Future<String?> getRecipeStatus(String recipeId) async {
    final uid = _requireUid();
    try {
      final data = await _client
          .from('user_recipes')
          .select('status')
          .eq('user_id', uid)
          .eq('recipe_id', recipeId)
          .maybeSingle();
      return data?['status'] as String?;
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw const AppException(
        'Could not check recipe status.',
        code: 'recipe_status_failed',
      );
    }
  }

  Future<Recipe?> findRecipeByCanonicalUrl(String canonicalUrl) async {
    try {
      final data = await _client
          .from('recipes')
          .select()
          .eq('canonical_url', canonicalUrl)
          .maybeSingle();
      if (data == null) return null;
      return Recipe.fromJson(data);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not look up the recipe. Please try again.',
        code: 'recipe_lookup_failed',
      );
    }
  }

  Future<Recipe> createRecipe(Recipe recipe) async {
    _log('Creating recipe: "${recipe.title}"');
    _requireUid();
    try {
      final data = await _client
          .from('recipes')
          .insert(recipe.toJson()..remove('id'))
          .select()
          .single();
      return Recipe.fromJson(data);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not save the recipe. Please try again.',
        code: 'recipe_create_failed',
      );
    }
  }

  Future<List<Recipe>> getUserRecipes({int limit = 5, int offset = 0}) async {
    final uid = _requireUid();
    try {
      final rows = await _client
          .from('user_recipes')
          .select('recipe_id, recipes(*)')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return rows
          .map((row) => Recipe.fromJson(row['recipes'] as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not load your recipes. Please try again.',
        code: 'recipes_fetch_failed',
      );
    }
  }

  Future<int> getUserRecipeCount() async {
    final uid = _requireUid();
    try {
      final response = await _client
          .from('user_recipes')
          .select()
          .eq('user_id', uid)
          .count(CountOption.exact);
      return response.count;
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not count your recipes.',
        code: 'recipe_count_failed',
      );
    }
  }

  Future<void> addRecipeToUser(String recipeId) async {
    final uid = _requireUid();
    try {
      await _client.from('user_recipes').insert({
        'user_id': uid,
        'recipe_id': recipeId,
      });
    } on PostgrestException catch (e) {
      // Ignore unique-violation — recipe already linked to the user.
      if (e.code == '23505') return;
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not link the recipe to your account.',
        code: 'recipe_link_failed',
      );
    }
  }

  Future<List<Recipe>> getPlatformRecipes({
    int limit = 20,
    int offset = 0,
    String? category,
  }) async {
    try {
      var query = _client
          .from('recipes')
          .select()
          .eq('is_platform_recipe', true);
      if (category != null) {
        query = query.eq('category', category);
      }
      final rows = await query
          .order('title', ascending: true)
          .range(offset, offset + limit - 1);
      return rows.map((row) => Recipe.fromJson(row)).toList();
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw const AppException(
        'Could not load recipes. Please try again.',
        code: 'platform_recipes_fetch_failed',
      );
    }
  }

  Future<List<Recipe>> searchPlatformRecipes(String query) async {
    try {
      final rows = await _client
          .from('recipes')
          .select()
          .eq('is_platform_recipe', true)
          .ilike('title', '%$query%')
          .order('title', ascending: true)
          .limit(20);
      return rows.map((row) => Recipe.fromJson(row)).toList();
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw const AppException(
        'Search failed. Please try again.',
        code: 'platform_search_failed',
      );
    }
  }

  Future<List<Recipe>> searchUserRecipes(String query) async {
    final uid = _requireUid();
    try {
      final rows = await _client
          .from('user_recipes')
          .select(
            'recipe_id, recipes(id, title, thumbnail_url, creator_name, canonical_url, video_url, cooking_time_minutes, portion_size, is_platform_recipe, created_by, created_at, ingredients, preparations, steps)',
          )
          .eq('user_id', uid)
          .ilike('recipes.title', '%$query%')
          .order('created_at', ascending: false);

      return rows
          .where((row) => row['recipes'] != null)
          .map((row) => Recipe.fromJson(row['recipes'] as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Search failed. Please try again.',
        code: 'recipe_search_failed',
      );
    }
  }

  Future<Recipe?> getActiveRecipe() async {
    final uid = _requireUid();
    try {
      final row = await _client
          .from('user_recipes')
          .select('recipe_id, recipes(*)')
          .eq('user_id', uid)
          .eq('status', 'in_progress')
          .maybeSingle();
      if (row == null) return null;
      return Recipe.fromJson(row['recipes'] as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not load the active recipe.',
        code: 'active_recipe_failed',
      );
    }
  }

  Future<void> updateRecipeState(
    String recipeId, {
    String? status,
    int? currentStepIndex,
    DateTime? startedAt,
    DateTime? completedAt,
  }) async {
    final uid = _requireUid();

    final updates = <String, dynamic>{
      'status': ?status,
      'current_step_index': ?currentStepIndex,
      if (startedAt != null) 'started_at': startedAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt.toIso8601String(),
    };


    if (updates.isEmpty) return;

    try {
      await _client
          .from('user_recipes')
          .update(updates)
          .eq('user_id', uid)
          .eq('recipe_id', recipeId);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not update recipe progress.',
        code: 'recipe_state_update_failed',
      );
    }
  }

  Future<void> completeAllActiveRecipes() async {
    final uid = _requireUid();
    try {
      await _client
          .from('user_recipes')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', uid)
          .eq('status', 'in_progress');
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not complete active recipes.',
        code: 'complete_active_failed',
      );
    }
  }

  // ──────────────────────────────────────────────────────────
  // DAILY LIMIT
  // ──────────────────────────────────────────────────────────

  /// Atomically checks the daily limit and increments the count if allowed.
  ///
  /// Calls the `check_and_increment_daily_limit` Postgres RPC which performs
  /// the check and increment in a single transaction, preventing race conditions
  /// when two requests run concurrently.
  ///
  /// Returns `(count, limit, allowed)` — if `allowed` is false, the caller
  /// should NOT proceed with recipe generation (limit already reached).
  /// The count is NOT incremented when `allowed` is false.
  Future<({int count, int limit, bool allowed})> checkAndIncrementDailyLimit() async {
    _log('Checking daily limit');
    final uid = _requireUid();
    try {
      final result = await _client.rpc(
        'check_and_increment_daily_limit',
        params: {'p_user_id': uid, 'p_date': _todayString()},
      ) as Map<String, dynamic>;

      final count = (result['count'] as int?) ?? 0;
      final limit = (result['limit'] as int?) ?? Env.dailyRecipeLimit;
      final allowed = (result['allowed'] as bool?) ?? false;
      return (count: count, limit: limit, allowed: allowed);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not check your daily limit.',
        code: 'daily_limit_check_failed',
      );
    }
  }

  /// Kept for backwards compatibility with any tooling scripts.
  /// Prefer [checkAndIncrementDailyLimit] in production flows.
  Future<({int count, int limit, bool allowed})> checkDailyLimit() async {
    final uid = _requireUid();
    try {
      final today = _todayString();
      final logRow = await _client
          .from('daily_generation_log')
          .select('count')
          .eq('user_id', uid)
          .eq('generation_date', today)
          .maybeSingle();
      final limitStr = await getConfig('daily_recipe_limit');
      final count = (logRow?['count'] as int?) ?? 0;
      final limit = int.tryParse(limitStr ?? '') ?? Env.dailyRecipeLimit;
      return (count: count, limit: limit, allowed: count < limit);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not check your daily limit.',
        code: 'daily_limit_check_failed',
      );
    }
  }

  Future<void> incrementDailyCount() async {
    final uid = _requireUid();
    try {
      await _client.rpc(
        'increment_daily_generation_count',
        params: {'p_user_id': uid, 'p_date': _todayString()},
      );
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not update your daily usage count.',
        code: 'daily_count_update_failed',
      );
    }
  }

  // ──────────────────────────────────────────────────────────
  // CONFIG
  // ──────────────────────────────────────────────────────────

  Future<String?> getConfig(String key) async {
    try {
      final data = await _client
          .from('app_config')
          .select('value')
          .eq('key', key)
          .maybeSingle();
      return data?['value'] as String?;
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } catch (e) {
      throw AppException(
        'Could not read app configuration.',
        code: 'config_read_failed',
      );
    }
  }

  Future<bool> isSignupEnabled() async {
    final value = await getConfig('signup_enabled');
    return value?.toLowerCase() == 'true';
  }

  // ──────────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ──────────────────────────────────────────────────────────

  String _requireUid() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const AppException(
        'You must be logged in to continue.',
        code: 'unauthenticated',
      );
    }
    return uid;
  }

  String _todayString() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  AppException _mapAuthException(AuthException e) {
    final code = e.statusCode?.toString();
    switch (code) {
      case '400':
        // OTP expired or invalid.
        return AppException(
          'Wrong OTP entered. Please check the OTP again.',
          code: 'invalid_otp',
        );
      case '422':
        return AppException(
          'This email address is not valid.',
          code: 'invalid_email',
        );
      case '429':
        return AppException(
          'Too many attempts. Please wait a moment and try again.',
          code: 'rate_limited',
        );
      default:
        return AppException(
          e.message.isNotEmpty
              ? e.message
              : 'An authentication error occurred.',
          code: 'auth_error_$code',
        );
    }
  }

  AppException _mapPostgrestException(PostgrestException e) {
    switch (e.code) {
      case '23505':
        return AppException('This record already exists.', code: 'duplicate');
      case '23503':
        return AppException(
          'A required reference was not found.',
          code: 'foreign_key',
        );
      case '42501':
        return AppException(
          'You do not have permission to perform this action.',
          code: 'forbidden',
        );
      case 'PGRST116':
        // .single() found no rows.
        return AppException(
          'The requested record was not found.',
          code: 'not_found',
        );
      default:
        return AppException(
          'Something went wrong. Please try again.',
          code: 'db_error_${e.code}',
        );
    }
  }
}
