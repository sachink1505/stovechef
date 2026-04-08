import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../models/recipe_step.dart';
import '../models/step_ingredient.dart';
import '../utils/url_utils.dart';
import 'app_exception.dart';
import 'supabase_service.dart';

class RecipeGeneratorService {
  RecipeGeneratorService._();
  static final RecipeGeneratorService instance = RecipeGeneratorService._();

  void _log(String msg) {
    if (kDebugMode) debugPrint('[RecipeGeneratorService] $msg');
  }

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  // NOTE: The Gemini API key is passed via the x-goog-api-key header rather
  // than a query parameter to avoid key exposure in server/proxy logs.
  // The key itself is injected at build time via --dart-define and compiled
  // into the binary. For production hardening, proxy this call through a
  // Supabase Edge Function so the key never leaves the server.

  // ──────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────

  Future<Recipe> generateRecipe({
    required String transcript,
    required String videoTitle,
    required String channelName,
    required String videoId,
  }) async {
    _log('Generating recipe for "$videoTitle" (id: $videoId)');
    final prompt = _buildPrompt(transcript, videoTitle, channelName);
    final responseText = await _callGemini(prompt);
    _log('Gemini response received, extracting JSON');
    final json = _extractJson(responseText);
    final recipe = _mapToRecipe(json, videoId: videoId, channelName: channelName);
    _log('Recipe mapped: "${recipe.title}" with ${recipe.steps.length} steps');
    return recipe;
  }

  // ──────────────────────────────────────────────────────────
  // Step 1 — Build prompt
  // ──────────────────────────────────────────────────────────

  String _buildPrompt(
      String transcript, String videoTitle, String channelName) {
    return '''
You are a culinary assistant. Given a transcript from a YouTube cooking video, extract a precise, structured recipe in JSON format.

Video title: $videoTitle
Channel: $channelName

Transcript:
$transcript

Return ONLY valid JSON (no markdown, no backticks) with this exact structure:
{
  "title": "Recipe name",
  "cooking_time_minutes": 30,
  "portion_size": 2,
  "ingredients": [
    {
      "name": "Onion",
      "quantity": "2 large or 200 grams",
      "prep_method": "finely chopped",
      "aliases": {"hindi": "pyaaz", "tamil": "vengayam", "telugu": "ullipaya", "kannada": "eerulli"}
    }
  ],
  "preparations": [
    "Soak rajma overnight in water",
    "Wash and drain the rajma"
  ],
  "steps": [
    {
      "step_number": 1,
      "title": "Chop vegetables",
      "description": "Finely chop 2 onions, mince 4 cloves of garlic, and dice 2 tomatoes.",
      "timer_seconds": null,
      "flame_level": null,
      "is_prep": true,
      "ingredients": [
        {"name": "Onion", "quantity": "2 large", "prep_method": "finely chopped"}
      ]
    },
    {
      "step_number": 2,
      "title": "Heat oil",
      "description": "Add 2 tablespoons of oil to a heavy-bottomed pan and heat on medium flame for 30 seconds.",
      "timer_seconds": 30,
      "flame_level": "medium",
      "is_prep": false,
      "ingredients": [
        {"name": "Oil", "quantity": "2 tablespoons", "prep_method": null}
      ]
    }
  ]
}

Rules:
- portion_size: extract from video, default to 2 if not mentioned.
- timer_seconds: ONLY for steps involving heat/gas stove. null for prep steps. Infer timing from context if not explicitly stated.
- flame_level: ONLY "low", "medium", or "high". null for prep steps.
- is_prep: true for steps with no cooking (chopping, mixing dry ingredients, soaking). false for anything on the stove.
- ingredients: include regional aliases in Hindi, Tamil, Telugu, and Kannada.
- preparations: list things to do before cooking starts (soaking, marinating, etc.). Empty array if none.
- Be precise with quantities. If the video says "some oil", estimate a reasonable amount.
- Order steps exactly as shown in the video.
- Separate prep and cooking into distinct steps.
''';
  }

  // ──────────────────────────────────────────────────────────
  // Step 2 — Call Gemini API
  // ──────────────────────────────────────────────────────────

  Future<String> _callGemini(String prompt) async {
    final uri = Uri.parse(_endpoint);

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.1,
        'maxOutputTokens': 4096,
      },
    });

    late http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': Env.geminiApiKey,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 60));
    } on SocketException {
      throw const AppException(
        'No internet connection.',
        code: 'no_internet',
      );
    } catch (_) {
      throw const AppException(
        'Recipe generation failed. Try again.',
        code: 'gemini_request_failed',
      );
    }

    if (response.statusCode == 429) {
      throw const AppException(
        'The recipe service is busy. Please wait 30 seconds and try again.',
        code: 'rate_limited',
      );
    }
    if (response.statusCode == 400) {
      // Most common cause: missing or invalid API key.
      throw const AppException(
        'Recipe generation failed. Check your Gemini API key and try again.',
        code: 'gemini_bad_request',
      );
    }
    if (response.statusCode >= 500) {
      throw const AppException(
        'Recipe generation failed. Try again.',
        code: 'gemini_error',
      );
    }
    if (response.statusCode != 200) {
      throw AppException(
        'Recipe generation failed (HTTP ${response.statusCode}). Try again.',
        code: 'gemini_http_error',
      );
    }

    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = (decoded['candidates'] as List<dynamic>?) ?? [];
      if (candidates.isEmpty) {
        throw const AppException(
          'Could not parse recipe. Try a different video.',
          code: 'gemini_empty_response',
        );
      }
      final content = candidates[0]['content'] as Map<String, dynamic>?;
      if (content == null) {
        throw const AppException(
          'Could not parse recipe. Try a different video.',
          code: 'gemini_empty_content',
        );
      }
      final parts = (content['parts'] as List<dynamic>?) ?? [];
      if (parts.isEmpty) {
        throw const AppException(
          'Could not parse recipe. Try a different video.',
          code: 'gemini_empty_parts',
        );
      }
      return parts[0]['text'] as String;
    } on AppException {
      rethrow;
    } catch (e) {
      throw const AppException(
        'Could not parse recipe. Try a different video.',
        code: 'gemini_parse_failed',
      );
    }
  }

  // ──────────────────────────────────────────────────────────
  // Step 3 — Extract and parse JSON from model response
  // ──────────────────────────────────────────────────────────

  Map<String, dynamic> _extractJson(String responseText) {
    var text = responseText.trim();

    // Strip accidental markdown fences: ```json ... ``` or ``` ... ```
    text = text.replaceFirst(RegExp(r'^```json\s*', multiLine: false), '');
    text = text.replaceFirst(RegExp(r'^```\s*', multiLine: false), '');
    text = text.replaceFirst(RegExp(r'\s*```$', multiLine: false), '');
    text = text.trim();

    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } on FormatException {
      throw const AppException(
        'Could not parse recipe. Try a different video.',
        code: 'json_parse_failed',
      );
    }
  }

  // ──────────────────────────────────────────────────────────
  // Step 4 — Map JSON to Recipe model
  // ──────────────────────────────────────────────────────────

  Recipe _mapToRecipe(
    Map<String, dynamic> json, {
    required String videoId,
    required String channelName,
  }) {
    try {
      final canonicalUrl =
          'https://www.youtube.com/watch?v=$videoId';
      final videoUrl = canonicalUrl;
      final thumbnailUrl = getThumbnailUrl(videoId);
      final currentUserId =
          SupabaseService.instance.getCurrentUser()?.id ?? '';

      final ingredients = (json['ingredients'] as List<dynamic>? ?? [])
          .map((e) => _mapIngredient(e as Map<String, dynamic>))
          .toList();

      final preparations = (json['preparations'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList();

      final steps = (json['steps'] as List<dynamic>? ?? [])
          .map((e) => _mapStep(e as Map<String, dynamic>))
          .toList();

      return Recipe(
        id: '', // assigned after Supabase insert
        videoUrl: videoUrl,
        canonicalUrl: canonicalUrl,
        title: (json['title'] as String?) ?? 'Untitled Recipe',
        creatorName: channelName,
        thumbnailUrl: thumbnailUrl,
        cookingTimeMinutes: (json['cooking_time_minutes'] as int?) ?? 0,
        portionSize: (json['portion_size'] as int?) ?? 2,
        isPlatformRecipe: false,
        createdBy: currentUserId,
        createdAt: DateTime.now(),
        ingredients: ingredients,
        preparations: preparations,
        steps: steps,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw const AppException(
        'Could not parse recipe. Try a different video.',
        code: 'model_mapping_failed',
      );
    }
  }

  Ingredient _mapIngredient(Map<String, dynamic> json) {
    final aliasesRaw = json['aliases'];
    List<String> aliases = [];

    if (aliasesRaw is Map<String, dynamic>) {
      aliases = aliasesRaw.values
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (aliasesRaw is List<dynamic>) {
      aliases = aliasesRaw.whereType<String>().toList();
    }

    return Ingredient(
      name: (json['name'] as String?) ?? '',
      quantity: (json['quantity'] as String?) ?? '',
      prepMethod: json['prep_method'] as String?,
      aliases: aliases,
    );
  }

  RecipeStep _mapStep(Map<String, dynamic> json) {
    final stepIngredients =
        (json['ingredients'] as List<dynamic>? ?? [])
            .map((e) => _mapStepIngredient(e as Map<String, dynamic>))
            .toList();

    return RecipeStep(
      stepNumber: (json['step_number'] as int?) ?? 0,
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      timerSeconds: json['timer_seconds'] as int?,
      flameLevel: FlameLevelX.fromJson(json['flame_level'] as String?),
      isPrep: (json['is_prep'] as bool?) ?? true,
      ingredients: stepIngredients,
    );
  }

  StepIngredient _mapStepIngredient(Map<String, dynamic> json) {
    return StepIngredient(
      name: (json['name'] as String?) ?? '',
      quantity: (json['quantity'] as String?) ?? '',
      prepMethod: json['prep_method'] as String?,
    );
  }
}
