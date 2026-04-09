import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/recipe.dart';
import '../utils/url_utils.dart';
import 'app_exception.dart';
import 'recipe_generator_service.dart';
import 'supabase_service.dart';
import 'transcript_service.dart';

// ──────────────────────────────────────────────────────────────
// Progress model
// ──────────────────────────────────────────────────────────────

enum RecipeCreationStage {
  validating,
  checkingExisting,
  extractingTranscript,
  generatingRecipe,
  saving,
  completed,
  failed,
}

class RecipeCreationProgress {
  final RecipeCreationStage stage;
  final double progress;
  final String message;
  final Recipe? recipe;
  final String? error;

  const RecipeCreationProgress({
    required this.stage,
    required this.progress,
    required this.message,
    this.recipe,
    this.error,
  });

  bool get isTerminal =>
      stage == RecipeCreationStage.completed ||
      stage == RecipeCreationStage.failed;
}

// ──────────────────────────────────────────────────────────────
// Service
// ──────────────────────────────────────────────────────────────

class RecipeCreationService {
  final TranscriptService _transcriptService;
  final RecipeGeneratorService _generatorService;
  final SupabaseService _supabaseService;

  bool _cancelled = false;

  void _log(String msg) {
    if (kDebugMode) debugPrint('[RecipeCreationService] $msg');
  }

  RecipeCreationService({
    required TranscriptService transcriptService,
    required RecipeGeneratorService generatorService,
    required SupabaseService supabaseService,
  })  : _transcriptService = transcriptService,
        _generatorService = generatorService,
        _supabaseService = supabaseService;

  void cancel() => _cancelled = true;

  Stream<RecipeCreationProgress> createRecipe(
    String youtubeUrl,
    String userId,
  ) async* {
    _cancelled = false;
    _log('Starting recipe creation for $youtubeUrl');

    // ── Stage 1: Validate URL ─────────────────────────────
    yield _progress(
      RecipeCreationStage.validating,
      0.05,
      'Validating link...',
    );

    if (_cancelled) return;

    String canonicalUrl;
    String videoId;
    try {
      final result = _validateUrl(youtubeUrl);
      canonicalUrl = result.canonicalUrl;
      videoId = result.videoId;
      _log('URL valid — videoId: $videoId');
    } on AppException catch (e) {
      _log('URL validation failed: ${e.message}');
      yield _failed(e.message);
      return;
    }

    // ── Stage 2: Check for existing recipe ────────────────
    yield _progress(
      RecipeCreationStage.checkingExisting,
      0.10,
      'Checking if recipe exists...',
    );

    if (_cancelled) return;

    try {
      final existing =
          await _supabaseService.findRecipeByCanonicalUrl(canonicalUrl);
      if (existing != null) {
        _log('Existing recipe found: ${existing.id}');
        await _supabaseService.addRecipeToUser(existing.id);
        yield _completed(existing);
        return;
      }
    } on AppException catch (e) {
      yield _failed(e.message);
      return;
    }

    // ── Stage 2b: Check daily limit (atomic check + reserve) ─
    // Uses a single RPC that checks and increments in one transaction,
    // preventing two concurrent requests from both passing the check.
    if (_cancelled) return;

    try {
      final limit = await _supabaseService.checkAndIncrementDailyLimit();
      if (!limit.allowed) {
        yield _failed(
          "You've reached today's limit of ${limit.limit} recipes. "
          'Try again tomorrow!',
        );
        return;
      }
    } on AppException catch (e) {
      yield _failed(e.message);
      return;
    }

    // ── Stage 3: Generate recipe (edge function → client fallback) ──
    yield _progress(
      RecipeCreationStage.extractingTranscript,
      0.25,
      'Extracting video information...',
    );

    if (_cancelled) return;

    late Recipe generatedRecipe;

    // Primary path: Supabase Edge Function (server-side transcript + Gemini)
    bool edgeFunctionSucceeded = false;
    AppException? edgeFunctionError;

    try {
      _log('Calling edge function for $videoId...');

      yield _progress(
        RecipeCreationStage.generatingRecipe,
        0.55,
        'Creating your recipe...',
      );

      generatedRecipe = await _withRetry(
          () => _generatorService.generateRecipeViaEdgeFunction(
                videoId: videoId,
              ));
      _log('Edge function recipe: "${generatedRecipe.title}"');
      edgeFunctionSucceeded = true;
    } on AppException catch (e) {
      _log('Edge function failed (${e.code}): ${e.message} — trying client-side fallback');
      edgeFunctionError = e;
    }

    if (_cancelled) return;

    // Fallback: client-side transcript extraction + direct Gemini call
    if (!edgeFunctionSucceeded) {
      _log('Starting client-side fallback...');

      yield _progress(
        RecipeCreationStage.extractingTranscript,
        0.35,
        'Watching the video...',
      );

      // Fetch metadata
      Map<String, String> metadata;
      try {
        metadata = await _withRetry(
            () => _transcriptService.getVideoMetadata(videoId));
        _log('Metadata fetched: title="${metadata['title']}", author="${metadata['author']}"');
      } on AppException catch (e) {
        _log('Metadata fetch failed: ${e.message}');
        // Surface the edge function error if it's more informative
        yield _failed(edgeFunctionError?.message ?? e.message);
        return;
      }

      if (_cancelled) return;

      // Try captions
      String? transcript;
      String transcriptLanguage = 'en';
      bool useAudio = false;

      _log('Trying to fetch captions (client-side)...');
      try {
        final result = await _withRetry(
            () => _transcriptService.getTranscript(videoId));
        transcript = result.text;
        transcriptLanguage = result.languageCode;
        _log('Captions found (${result.languageCode}), ${transcript.length} chars');
      } on AppException catch (e) {
        if (e.code == 'no_captions') {
          _log('No captions — will fall back to audio');
          useAudio = true;
        } else {
          _log('Caption fetch failed: ${e.code} - ${e.message}');
          yield _failed(edgeFunctionError?.message ?? e.message);
          return;
        }
      }

      if (_cancelled) return;

      yield _progress(
        RecipeCreationStage.generatingRecipe,
        0.55,
        'Creating your recipe...',
      );

      if (useAudio) {
        try {
          _log('Downloading audio for $videoId...');
          final audio = await _withRetry(
              () => _transcriptService.getAudioBytes(videoId));
          _log('Audio downloaded: ${audio.bytes.length} bytes, mime: ${audio.mimeType}');

          if (_cancelled) return;

          yield _progress(
            RecipeCreationStage.generatingRecipe,
            0.60,
            'Processing audio...',
          );

          _log('Calling Gemini with audio...');
          generatedRecipe = await _withRetry(() =>
              _generatorService.generateRecipeFromAudio(
                audioBytes: audio.bytes,
                mimeType: audio.mimeType,
                videoTitle: metadata['title'] ?? '',
                channelName: metadata['author'] ?? '',
                videoId: videoId,
              ));
          _log('Recipe generated from audio: "${generatedRecipe.title}"');
        } on AppException catch (e) {
          _log('Audio recipe generation failed: ${e.code} - ${e.message}');
          yield _failed(edgeFunctionError?.message ?? e.message);
          return;
        }
      } else {
        try {
          _log('Calling Gemini with transcript (${transcript!.length} chars, lang: $transcriptLanguage)...');
          generatedRecipe = await _withRetry(() =>
              _generatorService.generateRecipe(
                transcript: transcript!,
                transcriptLanguage: transcriptLanguage,
                videoTitle: metadata['title'] ?? '',
                channelName: metadata['author'] ?? '',
                videoId: videoId,
              ));
          _log('Recipe generated from transcript: "${generatedRecipe.title}"');
        } on AppException catch (e) {
          _log('Transcript recipe generation failed: ${e.code} - ${e.message}');
          yield _failed(edgeFunctionError?.message ?? e.message);
          return;
        }
      }
    }

    if (_cancelled) return;

    yield _progress(
      RecipeCreationStage.generatingRecipe,
      0.80,
      'Almost done...',
    );

    // ── Stage 5: Save ─────────────────────────────────────
    if (_cancelled) return;

    yield _progress(
      RecipeCreationStage.saving,
      0.90,
      'Saving recipe...',
    );

    try {
      _log('Saving recipe to Supabase...');
      final saved = await _supabaseService.createRecipe(generatedRecipe);
      _log('Recipe saved with id: ${saved.id}');
      await _supabaseService.addRecipeToUser(saved.id);
      _log('Recipe added to user library');
      // Daily count already incremented atomically in Stage 2b.
      yield _completed(saved);
    } on AppException catch (e) {
      _log('Save failed: ${e.code} - ${e.message}');
      yield _failed(e.message);
    }
  }

  // ──────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────

  /// Validates [url] and returns `(canonicalUrl, videoId)`.
  /// Throws [AppException] if invalid.
  ({String canonicalUrl, String videoId}) _validateUrl(String url) {
    final canonical = canonicalizeYouTubeUrl(url);
    if (canonical == null) {
      throw const AppException(
        'Invalid YouTube link. Please paste a valid video URL.',
        code: 'invalid_url',
      );
    }
    final videoId = extractVideoId(url) ?? '';
    if (videoId.isEmpty) {
      throw const AppException(
        'Invalid YouTube link. Please paste a valid video URL.',
        code: 'invalid_url',
      );
    }
    return (canonicalUrl: canonical, videoId: videoId);
  }

  /// Retries [fn] up to [maxAttempts] times on [AppException].
  ///
  /// - Rate-limited (429): waits 30 s + random jitter before each retry.
  /// - Other errors: exponential backoff starting at 2 s (2, 4, 8 …) + jitter.
  Future<T> _withRetry<T>(Future<T> Function() fn, {int maxAttempts = 3}) async {
    final rng = Random();
    late AppException lastError;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (attempt > 0) _log('_withRetry: attempt ${attempt + 1}/$maxAttempts');
        return await fn();
      } on AppException catch (e) {
        lastError = e;
        _log('_withRetry: attempt ${attempt + 1} failed: ${e.code} - ${e.message}');
        if (attempt == maxAttempts - 1) break; // no more retries

        final Duration base;
        if (e.code == 'rate_limited') {
          base = const Duration(seconds: 30);
          _log('_withRetry: rate limited, waiting 30s + jitter');
        } else {
          base = Duration(seconds: 2 * (1 << attempt)); // 2, 4, 8 …
          _log('_withRetry: waiting ${base.inSeconds}s + jitter before retry');
        }
        // Add up to 5 s of random jitter to avoid thundering herd.
        final jitter = Duration(milliseconds: rng.nextInt(5000));
        await Future.delayed(base + jitter);
      }
    }
    throw lastError;
  }

  RecipeCreationProgress _progress(
    RecipeCreationStage stage,
    double progress,
    String message,
  ) =>
      RecipeCreationProgress(
        stage: stage,
        progress: progress,
        message: message,
      );

  RecipeCreationProgress _failed(String error) => RecipeCreationProgress(
        stage: RecipeCreationStage.failed,
        progress: 0,
        message: error,
        error: error,
      );

  RecipeCreationProgress _completed(Recipe recipe) => RecipeCreationProgress(
        stage: RecipeCreationStage.completed,
        progress: 1.0,
        message: 'Recipe ready!',
        recipe: recipe,
      );
}
