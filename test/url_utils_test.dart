import 'package:flutter_test/flutter_test.dart';
import 'package:stovechef/utils/url_utils.dart';

void main() {
  const canonical = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
  const videoId = 'dQw4w9WgXcQ';

  // ── canonicalizeYouTubeUrl ────────────────────────────────

  group('canonicalizeYouTubeUrl', () {
    group('standard youtube.com/watch URLs', () {
      test('https with www', () {
        expect(
          canonicalizeYouTubeUrl('https://www.youtube.com/watch?v=$videoId'),
          canonical,
        );
      });

      test('https without www', () {
        expect(
          canonicalizeYouTubeUrl('https://youtube.com/watch?v=$videoId'),
          canonical,
        );
      });

      test('http (not https)', () {
        expect(
          canonicalizeYouTubeUrl('http://www.youtube.com/watch?v=$videoId'),
          canonical,
        );
      });

      test('missing scheme', () {
        expect(
          canonicalizeYouTubeUrl('www.youtube.com/watch?v=$videoId'),
          canonical,
        );
      });

      test('missing scheme and www', () {
        expect(
          canonicalizeYouTubeUrl('youtube.com/watch?v=$videoId'),
          canonical,
        );
      });
    });

    group('youtu.be short URLs', () {
      test('standard short URL', () {
        expect(
          canonicalizeYouTubeUrl('https://youtu.be/$videoId'),
          canonical,
        );
      });

      test('short URL without scheme', () {
        expect(
          canonicalizeYouTubeUrl('youtu.be/$videoId'),
          canonical,
        );
      });

      test('short URL with timestamp', () {
        expect(
          canonicalizeYouTubeUrl('https://youtu.be/$videoId?t=120'),
          canonical,
        );
      });
    });

    group('tracking and extra params are stripped', () {
      test('strips si= tracking param', () {
        expect(
          canonicalizeYouTubeUrl(
              'https://www.youtube.com/watch?v=$videoId&si=AbCdEfGhIjKlMnOp'),
          canonical,
        );
      });

      test('strips utm_source= param', () {
        expect(
          canonicalizeYouTubeUrl(
              'https://www.youtube.com/watch?v=$videoId&utm_source=share'),
          canonical,
        );
      });

      test('strips timestamp &t=', () {
        expect(
          canonicalizeYouTubeUrl(
              'https://www.youtube.com/watch?v=$videoId&t=120'),
          canonical,
        );
      });

      test('strips feature= param', () {
        expect(
          canonicalizeYouTubeUrl(
              'https://www.youtube.com/watch?v=$videoId&feature=youtu.be'),
          canonical,
        );
      });

      test('strips multiple junk params at once', () {
        expect(
          canonicalizeYouTubeUrl(
            'https://www.youtube.com/watch?v=$videoId&t=42&si=abc&feature=share',
          ),
          canonical,
        );
      });
    });

    group('Shorts URLs', () {
      test('standard shorts URL', () {
        expect(
          canonicalizeYouTubeUrl('https://www.youtube.com/shorts/$videoId'),
          canonical,
        );
      });

      test('shorts URL without www', () {
        expect(
          canonicalizeYouTubeUrl('https://youtube.com/shorts/$videoId'),
          canonical,
        );
      });

      test('shorts URL with trailing params', () {
        expect(
          canonicalizeYouTubeUrl(
              'https://www.youtube.com/shorts/$videoId?feature=share'),
          canonical,
        );
      });
    });

    group('mobile URLs', () {
      test('m.youtube.com/watch', () {
        expect(
          canonicalizeYouTubeUrl('https://m.youtube.com/watch?v=$videoId'),
          canonical,
        );
      });

      test('m.youtube.com with extra params', () {
        expect(
          canonicalizeYouTubeUrl(
              'https://m.youtube.com/watch?v=$videoId&t=30&si=xyz'),
          canonical,
        );
      });
    });

    group('playlist URLs — should be invalid', () {
      test('playlist URL is rejected', () {
        expect(
          canonicalizeYouTubeUrl(
              'https://www.youtube.com/playlist?list=PLxxx'),
          isNull,
        );
      });

      test('watch URL with list param — video ID is still valid', () {
        // The video itself is valid; we just strip the list param.
        expect(
          canonicalizeYouTubeUrl(
              'https://www.youtube.com/watch?v=$videoId&list=PLxxx&index=3'),
          canonical,
        );
      });
    });

    group('channel and non-video URLs — should be invalid', () {
      test('channel URL is rejected', () {
        expect(
          canonicalizeYouTubeUrl('https://www.youtube.com/channel/UCxxx'),
          isNull,
        );
      });

      test('handle URL is rejected', () {
        expect(
          canonicalizeYouTubeUrl('https://www.youtube.com/@someuser'),
          isNull,
        );
      });

      test('search results URL is rejected', () {
        expect(
          canonicalizeYouTubeUrl(
              'https://www.youtube.com/results?search_query=pasta'),
          isNull,
        );
      });
    });

    group('empty and garbage input', () {
      test('empty string returns null', () {
        expect(canonicalizeYouTubeUrl(''), isNull);
      });

      test('whitespace-only returns null', () {
        expect(canonicalizeYouTubeUrl('   '), isNull);
      });

      test('non-URL string returns null', () {
        expect(canonicalizeYouTubeUrl('not a url'), isNull);
      });

      test('non-YouTube URL returns null', () {
        expect(canonicalizeYouTubeUrl('https://vimeo.com/123456789'), isNull);
      });

      test('bare domain returns null', () {
        expect(canonicalizeYouTubeUrl('youtube.com'), isNull);
      });

      test('leading/trailing whitespace is trimmed', () {
        expect(
          canonicalizeYouTubeUrl(
              '  https://www.youtube.com/watch?v=$videoId  '),
          canonical,
        );
      });
    });
  });

  // ── extractVideoId ────────────────────────────────────────

  group('extractVideoId', () {
    test('extracts from standard URL', () {
      expect(
        extractVideoId('https://www.youtube.com/watch?v=$videoId'),
        videoId,
      );
    });

    test('extracts from youtu.be', () {
      expect(extractVideoId('https://youtu.be/$videoId'), videoId);
    });

    test('extracts from shorts', () {
      expect(
        extractVideoId('https://www.youtube.com/shorts/$videoId'),
        videoId,
      );
    });

    test('returns null for invalid input', () {
      expect(extractVideoId('https://example.com'), isNull);
    });

    test('returns null for empty string', () {
      expect(extractVideoId(''), isNull);
    });
  });

  // ── getThumbnailUrl ───────────────────────────────────────

  group('getThumbnailUrl', () {
    test('returns correct HQ thumbnail URL', () {
      expect(
        getThumbnailUrl(videoId),
        'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
      );
    });
  });

  // ── isValidYouTubeUrl ─────────────────────────────────────

  group('isValidYouTubeUrl', () {
    test('returns true for valid URL', () {
      expect(
        isValidYouTubeUrl('https://www.youtube.com/watch?v=$videoId'),
        isTrue,
      );
    });

    test('returns false for playlist URL', () {
      expect(
        isValidYouTubeUrl('https://www.youtube.com/playlist?list=PLxxx'),
        isFalse,
      );
    });

    test('returns false for empty string', () {
      expect(isValidYouTubeUrl(''), isFalse);
    });

    test('returns false for non-YouTube URL', () {
      expect(isValidYouTubeUrl('https://tiktok.com/@user/video/123'), isFalse);
    });
  });
}
