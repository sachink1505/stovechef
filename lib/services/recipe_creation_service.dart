import '../models/recipe.dart';
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
    } on AppException catch (e) {
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
        await _supabaseService.addRecipeToUser(existing.id);
        yield _completed(existing);
        return;
      }
    } on AppException catch (e) {
      yield _failed(e.message);
      return;
    }

    // ── Stage 2b: Check daily limit ───────────────────────
    if (_cancelled) return;

    try {
      final limit = await _supabaseService.checkDailyLimit();
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

    // ── Stage 3: Extract transcript ───────────────────────
    yield _progress(
      RecipeCreationStage.extractingTranscript,
      0.25,
      'Watching the video...',
    );

    if (_cancelled) return;

    String transcript;
    Map<String, String> metadata;
    try {
      final results = await _withRetry(() async {
        final t = await _transcriptService.getTranscript(videoId);
        final m = await _transcriptService.getVideoMetadata(videoId);
        return (t, m);
      });
      transcript = results.$1;
      metadata = results.$2;
    } on AppException catch (e) {
      yield _failed(e.message);
      return;
    }

    if (_cancelled) return;

    yield _progress(
      RecipeCreationStage.extractingTranscript,
      0.45,
      'Reading the recipe...',
    );

    // ── Stage 4: Generate recipe with Gemini ──────────────
    if (_cancelled) return;

    yield _progress(
      RecipeCreationStage.generatingRecipe,
      0.55,
      'Creating your recipe...',
    );

    Recipe generatedRecipe;
    try {
      generatedRecipe = await _withRetry(() => _generatorService.generateRecipe(
            transcript: transcript,
            videoTitle: metadata['title'] ?? '',
            channelName: metadata['author'] ?? '',
            videoId: videoId,
          ));
    } on AppException catch (e) {
      yield _failed(e.message);
      return;
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
      final saved = await _supabaseService.createRecipe(generatedRecipe);
      await _supabaseService.addRecipeToUser(saved.id);
      await _supabaseService.incrementDailyCount();
      yield _completed(saved);
    } on AppException catch (e) {
      yield _failed(e.message);
    }
  }

  // ──────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────

  /// Validates [url] and returns `(canonicalUrl, videoId)`.
  /// Throws [AppException] if invalid.
  ({String canonicalUrl, String videoId}) _validateUrl(String url) {
    // Reuse the same logic from url_utils but inline for error clarity.
    final canonical =
        // ignore: prefer_relative_imports
        _canonicalize(url);
    if (canonical == null) {
      throw const AppException(
        'Invalid YouTube link. Please paste a valid video URL.',
        code: 'invalid_url',
      );
    }
    final uri = Uri.parse(canonical);
    final videoId = uri.queryParameters['v'] ?? '';
    if (videoId.isEmpty) {
      throw const AppException(
        'Invalid YouTube link. Please paste a valid video URL.',
        code: 'invalid_url',
      );
    }
    return (canonicalUrl: canonical, videoId: videoId);
  }

  /// Retries [fn] once on [AppException]. Throws on second failure.
  /// Rate-limit errors (429) wait 30 s before retrying; others wait 2 s.
  Future<T> _withRetry<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on AppException catch (e) {
      final delay = e.code == 'rate_limited'
          ? const Duration(seconds: 30)
          : const Duration(seconds: 2);
      await Future.delayed(delay);
      return fn();
    }
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

// ──────────────────────────────────────────────────────────────
// Isolated import to avoid circular dependency in validate step
// ──────────────────────────────────────────────────────────────

String? _canonicalize(String url) {
  // Mirrors url_utils.canonicalizeYouTubeUrl without importing it
  // at the top level (url_utils has no service deps, so this is safe
  // to call directly — imported here via a local forwarding function
  // to keep the service layer clean).
  //
  // We import url_utils directly; the function is kept private to
  // this file to avoid exposing it.
  return _UrlUtils.canonicalize(url);
}

class _UrlUtils {
  static final _videoIdPattern = RegExp(r'^[\w-]{10,12}$');

  static String? canonicalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    Uri uri;
    try {
      final toParse =
          trimmed.startsWith('http') ? trimmed : 'https://$trimmed';
      uri = Uri.parse(toParse);
    } catch (_) {
      return null;
    }

    final host = uri.host.toLowerCase();
    if (!_isYouTubeDomain(host)) return null;

    final path = uri.path;
    if (_isNonVideoPath(path)) return null;

    String? id;
    if (host == 'youtu.be') {
      id = _pathSegment(path);
    } else if (path.startsWith('/shorts/')) {
      id = _pathSegment(path.substring('/shorts'.length));
    } else if (path == '/watch' || path.startsWith('/watch?')) {
      id = uri.queryParameters['v'];
    } else if (path.startsWith('/embed/')) {
      id = _pathSegment(path.substring('/embed'.length));
    } else if (path.startsWith('/v/')) {
      id = _pathSegment(path.substring('/v'.length));
    }

    if (id == null || !_videoIdPattern.hasMatch(id)) return null;
    return 'https://www.youtube.com/watch?v=$id';
  }

  static bool _isYouTubeDomain(String host) =>
      host == 'youtu.be' ||
      host == 'youtube.com' ||
      host == 'www.youtube.com' ||
      host == 'm.youtube.com' ||
      host == 'music.youtube.com';

  static bool _isNonVideoPath(String path) {
    const rejected = [
      '/playlist',
      '/channel',
      '/c/',
      '/user/',
      '/@',
      '/feed',
      '/results',
    ];
    return rejected.any((p) => path.startsWith(p));
  }

  static String? _pathSegment(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isNotEmpty ? segments.first : null;
  }
}
