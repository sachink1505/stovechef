import 'package:flutter_test/flutter_test.dart';

import 'package:stovechef/utils/url_utils.dart';

void main() {
  test('canonicalizeYouTubeUrl normalizes standard URL', () {
    expect(
      canonicalizeYouTubeUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc'),
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );
  });

  test('canonicalizeYouTubeUrl handles youtu.be', () {
    expect(
      canonicalizeYouTubeUrl('https://youtu.be/dQw4w9WgXcQ'),
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );
  });

  test('canonicalizeYouTubeUrl rejects non-YouTube', () {
    expect(canonicalizeYouTubeUrl('https://vimeo.com/123'), isNull);
  });
}
