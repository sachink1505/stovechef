// Matches YouTube video IDs — typically 11 chars, but the spec allows
// alphanumeric + hyphen + underscore between 10–12 chars in practice.
final _videoIdPattern = RegExp(r'^[\w-]{10,12}$');

// ─────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────

/// Normalises any YouTube video URL to its canonical form:
///   https://www.youtube.com/watch?v=VIDEO_ID
///
/// Returns `null` for:
/// - Non-YouTube URLs
/// - Playlist / channel / non-video URLs
/// - URLs whose video ID doesn't look valid
String? canonicalizeYouTubeUrl(String input) {
  final id = extractVideoId(input);
  if (id == null) return null;
  return 'https://www.youtube.com/watch?v=$id';
}

/// Extracts and returns the raw VIDEO_ID from any recognised YouTube URL.
/// Returns `null` for invalid or non-video URLs.
String? extractVideoId(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  Uri uri;
  try {
    // Prepend scheme if missing so Uri.parse works correctly.
    final toparse =
        trimmed.startsWith('http') ? trimmed : 'https://$trimmed';
    uri = Uri.parse(toparse);
  } catch (_) {
    return null;
  }

  final host = uri.host.toLowerCase();

  // Must be a YouTube domain.
  if (!_isYouTubeDomain(host)) return null;

  final path = uri.path;

  // ── Reject non-video paths up-front ──────────────────────
  if (_isNonVideoPath(path)) return null;

  String? id;

  // youtu.be/VIDEO_ID
  if (host == 'youtu.be') {
    id = _extractFromPath(path);
  }
  // youtube.com/shorts/VIDEO_ID
  else if (path.startsWith('/shorts/')) {
    id = _extractFromPath(path.substring('/shorts'.length));
  }
  // youtube.com/watch?v=VIDEO_ID  (or /watch/VIDEO_ID — rare but seen)
  else if (path == '/watch' || path.startsWith('/watch?')) {
    id = uri.queryParameters['v'];
  }
  // youtube.com/embed/VIDEO_ID
  else if (path.startsWith('/embed/')) {
    id = _extractFromPath(path.substring('/embed'.length));
  }
  // youtube.com/v/VIDEO_ID  (old embed)
  else if (path.startsWith('/v/')) {
    id = _extractFromPath(path.substring('/v'.length));
  }

  if (id == null || !_videoIdPattern.hasMatch(id)) return null;
  return id;
}

/// Returns the HQ thumbnail URL for a given video ID.
String getThumbnailUrl(String videoId) =>
    'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

/// Returns `true` if [input] is a valid YouTube video URL.
bool isValidYouTubeUrl(String input) => canonicalizeYouTubeUrl(input) != null;

// ─────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────

bool _isYouTubeDomain(String host) {
  return host == 'youtu.be' ||
      host == 'youtube.com' ||
      host == 'www.youtube.com' ||
      host == 'm.youtube.com' ||
      host == 'music.youtube.com';
}

/// Rejects paths that are clearly not individual video pages.
bool _isNonVideoPath(String path) {
  const rejected = [
    '/playlist',
    '/channel',
    '/c/',
    '/user/',
    '/@',
    '/feed',
    '/results',
    '/live',
  ];
  for (final prefix in rejected) {
    if (path.startsWith(prefix)) return true;
  }
  return false;
}

/// Extracts the first path segment after a leading slash.
/// e.g. "/dQw4w9WgXcQ" → "dQw4w9WgXcQ"
///      "/dQw4w9WgXcQ?t=60" — already stripped by Uri.path
String? _extractFromPath(String path) {
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isNotEmpty ? segments.first : null;
}
