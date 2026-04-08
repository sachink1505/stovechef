import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_exception.dart';

class TranscriptService {
  TranscriptService._();
  static final TranscriptService instance = TranscriptService._();

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const _headers = {'User-Agent': _userAgent};

  // ──────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────

  /// Fetches and returns the full transcript text for [videoId].
  Future<String> getTranscript(String videoId) async {
    final playerResponse = await _fetchPlayerResponse(videoId);

    final captionUrl = _selectCaptionTrackUrl(playerResponse);
    if (captionUrl == null) {
      throw const AppException(
        'This video has no captions. Try a different video.',
        code: 'no_captions',
      );
    }

    final xml = await _fetchCaptionXml(captionUrl);
    return _parseTranscriptFromXml(xml);
  }

  /// Extracts basic metadata for [videoId] from ytInitialPlayerResponse.
  ///
  /// Returns a map with keys: `title`, `author`, `lengthSeconds`.
  Future<Map<String, String>> getVideoMetadata(String videoId) async {
    final playerResponse = await _fetchPlayerResponse(videoId);

    final videoDetails =
        playerResponse['videoDetails'] as Map<String, dynamic>?;
    if (videoDetails == null) {
      throw const AppException(
        'This video is unavailable or private.',
        code: 'video_unavailable',
      );
    }

    return {
      'title': (videoDetails['title'] as String?) ?? '',
      'author': (videoDetails['author'] as String?) ?? '',
      'lengthSeconds': (videoDetails['lengthSeconds'] as String?) ?? '0',
    };
  }

  // ──────────────────────────────────────────────────────────
  // Step 1 — Fetch and parse ytInitialPlayerResponse
  // ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _fetchPlayerResponse(String videoId) async {
    final uri =
        Uri.parse('https://www.youtube.com/watch?v=$videoId&hl=en');

    late http.Response response;
    try {
      response = await http.get(uri, headers: _headers).timeout(
            const Duration(seconds: 15),
          );
    } on SocketException {
      throw const AppException(
        'No internet connection.',
        code: 'no_internet',
      );
    } on HttpException {
      throw const AppException(
        'No internet connection.',
        code: 'no_internet',
      );
    } catch (_) {
      throw const AppException(
        'No internet connection.',
        code: 'no_internet',
      );
    }

    if (response.statusCode == 404 || response.statusCode == 410) {
      throw const AppException(
        'This video is unavailable or private.',
        code: 'video_unavailable',
      );
    }
    if (response.statusCode != 200) {
      throw AppException(
        'Could not load the video page (HTTP ${response.statusCode}).',
        code: 'http_error',
      );
    }

    final html = response.body;

    // ytInitialPlayerResponse is assigned as a JS variable:
    //   var ytInitialPlayerResponse = {...};
    // We grab everything between the first `{` and the matching `};`.
    final marker = 'var ytInitialPlayerResponse = ';
    final start = html.indexOf(marker);
    if (start == -1) {
      throw const AppException(
        'This video is unavailable or private.',
        code: 'video_unavailable',
      );
    }

    final jsonStart = html.indexOf('{', start + marker.length);
    if (jsonStart == -1) {
      throw const AppException(
        'This video is unavailable or private.',
        code: 'video_unavailable',
      );
    }

    // Walk forward to find the balanced closing `};`
    final jsonEnd = _findJsonObjectEnd(html, jsonStart);
    if (jsonEnd == -1) {
      throw const AppException(
        'This video is unavailable or private.',
        code: 'video_unavailable',
      );
    }

    final jsonStr = html.substring(jsonStart, jsonEnd + 1);
    try {
      return json.decode(jsonStr) as Map<String, dynamic>;
    } on FormatException {
      throw const AppException(
        'This video is unavailable or private.',
        code: 'video_unavailable',
      );
    }
  }

  // ──────────────────────────────────────────────────────────
  // Step 2 — Select best caption track URL
  // ──────────────────────────────────────────────────────────

  /// Returns the `baseUrl` of the best caption track, or `null` if none exist.
  ///
  /// Priority:
  ///   1. Manual English track (vssId starts with `.en` or languageCode `en`)
  ///   2. Auto-generated English track (kind: "asr", languageCode: "en")
  ///   3. Any auto-generated track (kind: "asr")
  ///   4. Any available track
  String? _selectCaptionTrackUrl(Map<String, dynamic> playerResponse) {
    final captions =
        playerResponse['captions'] as Map<String, dynamic>?;
    if (captions == null) return null;

    final renderer = captions['playerCaptionsTracklistRenderer']
        as Map<String, dynamic>?;
    if (renderer == null) return null;

    final tracks = renderer['captionTracks'] as List<dynamic>?;
    if (tracks == null || tracks.isEmpty) return null;

    final typedTracks = tracks.cast<Map<String, dynamic>>();

    // Score each track; higher = better.
    Map<String, dynamic>? best;
    int bestScore = -1;

    for (final track in typedTracks) {
      final lang = (track['languageCode'] as String? ?? '').toLowerCase();
      final kind = track['kind'] as String? ?? '';
      final vssId = (track['vssId'] as String? ?? '').toLowerCase();
      final isEnglish = lang.startsWith('en') || vssId.contains('.en');
      final isManual = kind != 'asr';

      final int score;
      if (isEnglish && isManual) {
        score = 4;
      } else if (isEnglish && !isManual) {
        score = 3;
      } else if (!isEnglish && isManual) {
        score = 2;
      } else {
        score = 1; // any asr, any language
      }

      if (score > bestScore) {
        bestScore = score;
        best = track;
      }
    }

    if (best == null) return null;

    var url = best['baseUrl'] as String?;
    if (url == null) return null;

    // Request JSON format if possible (cleaner than XML), otherwise keep XML.
    // The default format is ttml/xml; we explicitly request srv3 (JSON-like).
    // Actually, the XML (srv1) format is more reliable — stick with it.
    if (!url.contains('&fmt=')) {
      url = '$url&fmt=srv1';
    }

    return url;
  }

  // ──────────────────────────────────────────────────────────
  // Step 3 — Fetch caption XML
  // ──────────────────────────────────────────────────────────

  Future<String> _fetchCaptionXml(String captionUrl) async {
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse(captionUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
    } on SocketException {
      throw const AppException('No internet connection.', code: 'no_internet');
    } catch (_) {
      throw const AppException('No internet connection.', code: 'no_internet');
    }

    if (response.statusCode != 200) {
      throw const AppException(
        'This video has no captions. Try a different video.',
        code: 'no_captions',
      );
    }

    return response.body;
  }

  // ──────────────────────────────────────────────────────────
  // Step 4 — Parse XML into plain text
  // ──────────────────────────────────────────────────────────

  /// Extracts text content from all `<text>` elements in the caption XML,
  /// decodes HTML entities, and returns the joined transcript.
  ///
  /// The caption XML looks like:
  /// ```xml
  ///   <transcript>
  ///     <text start="0.5" dur="2.3">Hello &amp; welcome</text>
  ///     ...
  ///   </transcript>
  /// ```
  String _parseTranscriptFromXml(String xml) {
    // Extract all <text ...>content</text> segments.
    final textTagPattern = RegExp(r'<text[^>]*>([\s\S]*?)</text>');
    final matches = textTagPattern.allMatches(xml);

    if (matches.isEmpty) {
      throw const AppException(
        'This video has no captions. Try a different video.',
        code: 'no_captions',
      );
    }

    final parts = matches
        .map((m) => _decodeHtmlEntities(m.group(1) ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return parts.join(' ');
  }

  // ──────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────

  /// Decodes common HTML entities found in YouTube caption XML.
  String _decodeHtmlEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('\n', ' ')
        // Strip any remaining inline XML/HTML tags (e.g. <font color=...>)
        .replaceAll(RegExp(r'<[^>]+>'), '');
  }

  /// Finds the index of the closing `}` that matches the `{` at [start].
  /// Returns -1 if not found.
  int _findJsonObjectEnd(String source, int start) {
    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = start; i < source.length; i++) {
      final ch = source[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (ch == r'\' && inString) {
        escaped = true;
        continue;
      }

      if (ch == '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }
}
