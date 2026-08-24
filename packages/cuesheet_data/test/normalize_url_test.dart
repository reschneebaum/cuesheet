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

  group('regressions the real corpus found', () {
    test('an origin host is not a wrapper just because a wrapper points at it',
        () {
      // `traffic.megaphone.fm/` was in the old prefix list, so every Megaphone
      // episode normalized to `https://cfq4592230655.mp3` — a bogus host with
      // the path thrown away.
      expect(norm('https://traffic.megaphone.fm/CFQ4592230655.mp3'),
          'https://traffic.megaphone.fm/CFQ4592230655.mp3');
    });

    test('unwraps the five-deep chain a real Megaphone feed ships', () {
      expect(
        norm('https://www.podtrac.com/pts/redirect.mp3/pdst.fm/e/pscrb.fm/rss/p/'
            'clrtpod.com/m/mgln.ai/e/204/traffic.megaphone.fm/CTL2664471402.mp3'),
        'https://traffic.megaphone.fm/CTL2664471402.mp3',
      );
    });

    test('drops the per-episode ids that the case mismatch was leaving in', () {
      // The denylist held `awCollectionId` and compared it lowercased, so it
      // matched nothing and both ids stayed in the key.
      expect(
        norm('https://dts.podtrac.com/redirect.mp3/'
            'stitcher.simplecastaudio.com/ca05/episodes/ec2c/audio/128/default.mp3'
            '?aid=rss_feed&awCollectionId=ca05&awEpisodeId=ec2c&feed=6Qp23t6h'),
        'https://stitcher.simplecastaudio.com/ca05/episodes/ec2c/audio/128/'
            'default.mp3',
      );
    });

    test('drops Megaphone\'s re-upload timestamp', () {
      // `updated` changes when an episode is re-cut, which is precisely when
      // rung 2 has work to do.
      expect(
        norm('https://traffic.megaphone.fm/CFQ1.mp3?updated=1770999214'),
        norm('https://traffic.megaphone.fm/CFQ1.mp3?updated=1774672335'),
      );
    });
  });

  group('unwrapping is gated on the host', () {
    test('a path segment that looks like a host is left alone', () {
      // The dangerous direction. `my.show` looks exactly like a hostname, and
      // re-rooting there would invent a URL that fetches nothing.
      expect(norm('https://cdn.example.com/shows/my.show/ep1.mp3'),
          'https://cdn.example.com/shows/my.show/ep1.mp3');
    });

    test('a file extension is not mistaken for a TLD', () {
      // `redirect.mp3` sits between the wrapper and the payload on podtrac.
      expect(norm('https://dts.podtrac.com/redirect.mp3/cdn.example.com/a.mp3'),
          'https://cdn.example.com/a.mp3');
    });

    test('unwraps a wrapper that embeds the whole URL, scheme and all', () {
      expect(norm('https://op3.dev/e/https://cdn.example.com/a.mp3'),
          'https://cdn.example.com/a.mp3');
    });

    test('a wrapper with nothing host-shaped after it is left as it is', () {
      expect(norm('https://pdst.fm/e/'), 'https://pdst.fm/e/');
    });

    test('stops rather than looping on a self-referential chain', () {
      // Bounded depth. A feed must not be able to hang ingestion.
      final absurd = 'https://pdst.fm/e/' * 40;
      expect(() => norm('https://pdst.fm/e/$absurd/cdn.example.com/a.mp3'),
          returnsNormally);
    });
  });
}
