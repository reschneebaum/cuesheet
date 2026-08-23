import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:test/test.dart';

String norm(String url) => normalizeEnclosureUrl(Uri.parse(url));

void main() {
  test('leaves a plain URL alone apart from casing the host', () {
    expect(norm('https://CDN.Example.com/a.mp3'),
        'https://cdn.example.com/a.mp3');
  });

  test('unwraps a tracking redirect to the real file', () {
    expect(
      norm('https://dts.podtrac.com/redirect.mp3/cdn.example.com/a.mp3'),
      'https://cdn.example.com/a.mp3',
    );
  });

  test('unwraps stacked redirects, innermost wins', () {
    expect(
      norm('https://chtbl.com/track/1234/dts.podtrac.com/redirect.mp3/'
          'cdn.example.com/a.mp3'),
      'https://cdn.example.com/a.mp3',
    );
  });

  test('drops campaign parameters but keeps meaningful ones', () {
    expect(
      norm('https://cdn.example.com/a.mp3?utm_source=rss&token=abc'),
      'https://cdn.example.com/a.mp3?token=abc',
    );
  });

  test('a wrapped and a bare URL normalize to the same key', () {
    // The whole point: a host adding analytics must not look like a new episode.
    expect(
      norm('https://dts.podtrac.com/redirect.mp3/cdn.example.com/a.mp3?utm_medium=rss'),
      norm('https://cdn.example.com/a.mp3'),
    );
  });
}
