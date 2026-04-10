import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';

  // ──────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────

  Future<Recipe> generateRecipe({
    required String transcript,
    String transcriptLanguage = 'en',
    required String videoTitle,
    required String channelName,
    required String videoId,
  }) async {
    _log('Generating recipe for "$videoTitle" (id: $videoId, lang: $transcriptLanguage)');
    final prompt = _buildPrompt(transcript, videoTitle, channelName, transcriptLanguage);
    final responseText = await _callGemini(prompt);
    _log('Gemini response received, extracting JSON');
    final json = _extractJson(responseText);
    final recipe = _mapToRecipe(json, videoId: videoId, channelName: channelName);
    _log('Recipe mapped: "${recipe.title}" with ${recipe.steps.length} steps');
    return recipe;
  }

  /// Generates a recipe by sending audio directly to Gemini.
  /// Used as a fallback when no captions are available.
  Future<Recipe> generateRecipeFromAudio({
    required Uint8List audioBytes,
    required String mimeType,
    required String videoTitle,
    required String channelName,
    required String videoId,
  }) async {
    _log('Generating recipe from audio for "$videoTitle" (id: $videoId, ${audioBytes.length} bytes)');
    final prompt = _buildAudioPrompt(videoTitle, channelName);
    final responseText = await _callGeminiWithAudio(prompt, audioBytes, mimeType);
    _log('Gemini audio response received, extracting JSON');
    final json = _extractJson(responseText);
    final recipe = _mapToRecipe(json, videoId: videoId, channelName: channelName);
    _log('Recipe mapped: "${recipe.title}" with ${recipe.steps.length} steps');
    return recipe;
  }

  /// Generates a recipe via the Supabase Edge Function.
  ///
  /// The edge function fetches the transcript from YouTube (server-side,
  /// using the innertube ANDROID API) and calls Gemini, returning the
  /// complete recipe JSON in one round trip.
  Future<Recipe> generateRecipeViaEdgeFunction({
    required String videoId,
    String? transcript,
    String? transcriptLang,
    String? title,
    String? author,
  }) async {
    _log('Calling edge function for videoId: $videoId (transcript: ${transcript != null ? "${transcript.length} chars" : "none"})');
    final stopwatch = Stopwatch()..start();

    final body = <String, dynamic>{'videoId': videoId};
    if (transcript != null) {
      body['transcript'] = transcript;
      body['transcriptLang'] = transcriptLang ?? 'en';
      body['title'] = title ?? '';
      body['author'] = author ?? '';
    }

    late final FunctionResponse response;
    try {
      response = await Supabase.instance.client.functions.invoke(
        'generate-recipe',
        body: body,
      );
      _log('Edge function responded in ${stopwatch.elapsedMilliseconds}ms, status: ${response.status}');
    } on FunctionException catch (e) {
      _log('Edge function FunctionException: $e');
      throw AppException(
        'Recipe generation failed. Try again.',
        code: 'edge_function_error',
      );
    } catch (e) {
      _log('Edge function call failed: $e');
      throw const AppException(
        'Recipe generation failed. Try again.',
        code: 'edge_function_error',
      );
    }

    if (response.status != 200) {
      final data = response.data;
      String code = 'edge_function_error';
      String message = 'Recipe generation failed.';

      if (data is Map<String, dynamic>) {
        code = (data['error'] as String?) ?? code;
        message = (data['message'] as String?) ?? message;
      }

      _log('Edge function error ($code): $message');
      throw AppException(message, code: code);
    }

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      _log('Edge function returned non-map data: ${data.runtimeType}');
      throw const AppException(
        'Could not parse recipe. Try a different video.',
        code: 'edge_function_parse_error',
      );
    }

    final recipeJson = data['recipe'] as Map<String, dynamic>?;
    if (recipeJson == null) {
      _log('Edge function response missing "recipe" key');
      throw const AppException(
        'Could not parse recipe. Try a different video.',
        code: 'edge_function_parse_error',
      );
    }

    final metadata = data['metadata'] as Map<String, dynamic>?;
    final channelName = (metadata?['author'] as String?) ?? '';

    final recipe = _mapToRecipe(recipeJson, videoId: videoId, channelName: channelName);
    _log('Edge function recipe mapped: "${recipe.title}" with ${recipe.steps.length} steps');
    return recipe;
  }

  // ──────────────────────────────────────────────────────────
  // Step 1 — Build prompt
  // ──────────────────────────────────────────────────────────

  String _buildPrompt(
      String transcript, String videoTitle, String channelName, String transcriptLanguage) {
    final langNote = transcriptLanguage.startsWith('en')
        ? ''
        : '\n\nIMPORTANT: The transcript is in language code "$transcriptLanguage" (not English). '
          'Understand the transcript in its original language but return ALL recipe output (title, '
          'descriptions, ingredient names, step instructions) in English.\n';

    return '''
You are a culinary assistant. Given a transcript from a YouTube cooking video, extract a precise, structured recipe in JSON format.

Video title: $videoTitle
Channel: $channelName$langNote

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

  /// Prompt for audio-based generation (no transcript available).
  String _buildAudioPrompt(String videoTitle, String channelName) {
    return '''
You are a culinary assistant. Listen to the audio from a YouTube cooking video and extract a precise, structured recipe in JSON format.

The audio may be in any language (Hindi, Tamil, Telugu, Kannada, English, or other Indian languages). Understand the audio in its original language but return ALL recipe output in English.

Video title: $videoTitle
Channel: $channelName

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
    if (Env.geminiApiKey.isEmpty) {
      _log('_callGemini: GEMINI_API_KEY is empty! Was --dart-define passed?');
      throw const AppException(
        'Recipe service is not configured. Please check your API key.',
        code: 'missing_api_key',
      );
    }
    _log('_callGemini: preparing request (prompt length: ${prompt.length})');
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

    _log('_callGemini: sending POST to Gemini (body size: ${body.length} bytes)');
    final stopwatch = Stopwatch()..start();
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
      _log('_callGemini: response received in ${stopwatch.elapsedMilliseconds}ms, status: ${response.statusCode}');
    } on SocketException {
      _log('_callGemini: SocketException after ${stopwatch.elapsedMilliseconds}ms');
      throw const AppException(
        'No internet connection.',
        code: 'no_internet',
      );
    } catch (e) {
      _log('_callGemini: exception after ${stopwatch.elapsedMilliseconds}ms: $e');
      throw const AppException(
        'Recipe generation failed. Try again.',
        code: 'gemini_request_failed',
      );
    }

    if (response.statusCode == 429) {
      _log('_callGemini: rate limited (429). Response: ${response.body}');
      throw const AppException(
        'The recipe service is busy. Please wait a moment and try again.',
        code: 'rate_limited',
      );
    }
    if (response.statusCode == 400) {
      _log('_callGemini: bad request (400). Response: ${response.body}');
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
    } catch (_) {
      throw const AppException(
        'Could not parse recipe. Try a different video.',
        code: 'gemini_parse_failed',
      );
    }
  }

  /// Calls Gemini with audio bytes + text prompt (multimodal).
  Future<String> _callGeminiWithAudio(
      String prompt, Uint8List audioBytes, String mimeType) async {
    if (Env.geminiApiKey.isEmpty) {
      _log('_callGeminiWithAudio: GEMINI_API_KEY is empty! Was --dart-define passed?');
      throw const AppException(
        'Recipe service is not configured. Please check your API key.',
        code: 'missing_api_key',
      );
    }
    _log('_callGeminiWithAudio: encoding ${audioBytes.length} bytes as base64');
    final uri = Uri.parse(_endpoint);
    final audioBase64 = base64Encode(audioBytes);
    _log('_callGeminiWithAudio: base64 size: ${audioBase64.length} chars');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'inline_data': {
                'mime_type': mimeType,
                'data': audioBase64,
              },
            },
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.1,
        'maxOutputTokens': 4096,
      },
    });

    _log('_callGeminiWithAudio: sending POST to Gemini (body size: ${body.length} bytes)');
    final stopwatch = Stopwatch()..start();
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
          .timeout(const Duration(seconds: 120));
      _log('_callGeminiWithAudio: response received in ${stopwatch.elapsedMilliseconds}ms, status: ${response.statusCode}');
    } on SocketException {
      _log('_callGeminiWithAudio: SocketException after ${stopwatch.elapsedMilliseconds}ms');
      throw const AppException('No internet connection.', code: 'no_internet');
    } catch (e) {
      _log('_callGeminiWithAudio: exception after ${stopwatch.elapsedMilliseconds}ms: $e');
      throw const AppException(
        'Recipe generation failed. Try again.',
        code: 'gemini_request_failed',
      );
    }

    if (response.statusCode == 429) {
      _log('_callGeminiWithAudio: rate limited (429)');
      throw const AppException(
        'The recipe service is busy. Please wait 30 seconds and try again.',
        code: 'rate_limited',
      );
    }
    if (response.statusCode == 400) {
      _log('Gemini 400 response: ${response.body}');
      throw const AppException(
        'Recipe generation failed. Try a different video.',
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
    } catch (_) {
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
    _log('_extractJson: response length ${responseText.length}, first 200 chars: ${responseText.substring(0, responseText.length.clamp(0, 200))}');
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
