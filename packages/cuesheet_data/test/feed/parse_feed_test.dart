import 'dart:io';

import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:test/test.dart';

ParsedFeed fixture(String name) =>
    parseFeed(File('test/fixtures/feeds/$name').readAsStringSync());

void main() {
  group('a feed with nothing wrong with it', () {
    late ParsedFeed feed;
    setUp(() => feed = fixture('clean.xml'));

    test('reads the channel', () {
      expect(feed.title, 'The Cartographers');
      expect(feed.author, 'Wren Alvarez');
      expect(feed.description, 'Conversations about maps.');
      expect(feed.artworkUrl,
          Uri.parse('https://cdn.cartographers.example/art/cover.jpg'));
      expect(feed.warnings, isEmpty);
    });

    test('reads every item, in feed order', () {
      expect(feed.items.map((i) => i.title), [
        'The Mercator Problem',
        'Contour Lines',
        'Projections, Briefly',
      ]);
      expect(feed.items.map((i) => i.feedPosition), [0, 1, 2]);
    });

    test('reads the fields of an item', () {
      final first = feed.items.first;
      expect(first.guid, 'cartographers-0042');
      expect(first.publishedAt, DateTime.utc(2025, 6, 10, 9));
      expect(first.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(first.enclosureUrl,
          Uri.parse('https://cdn.cartographers.example/audio/0042.mp3'));
      expect(first.artworkUrl,
          Uri.parse('https://cdn.cartographers.example/art/0042.jpg'));
    });

    test('prefers content:encoded over description, and keeps its HTML', () {
      // Show notes are legitimately markup. The column stores what the feed
      // sent; plain text can be derived later, the reverse cannot.
      expect(feed.items.first.description,
          '<p>Why <em>Greenland</em> is a lie.</p>');
    });

    test('falls back to description when there is no content:encoded', () {
      expect(feed.items[1].description, 'Reading elevation.');
    });

    test('leaves description null when the feed supplies none', () {
      expect(feed.items[2].description, isNull);
    });
  });

  group('missing guids and dates', () {
    late ParsedFeed feed;
    setUp(() => feed = fixture('no_guids_or_dates.xml'));

    test('an absent, empty or blank guid all read as null', () {
      // Not as the empty string: three episodes that all "have" guid "" would
      // collide on the first rung of the identity ladder and become one.
      expect(feed.items.map((i) => i.guid), [null, null, null]);
    });

    test('an unreadable date is null, and says so', () {
      expect(feed.items.map((i) => i.publishedAt), [null, null, null]);
      expect(feed.warnings, hasLength(1));
      expect(feed.warnings.single, contains('whenever we got round to it'));
    });

    test('an absent date is not a warning, only an unreadable one is', () {
      expect(feed.warnings.where((w) => w.contains('#0')), isEmpty);
      expect(feed.warnings.where((w) => w.contains('#1')), isEmpty);
    });
  });

  group('markup in fields specified as plain text', () {
    late ParsedFeed feed;
    setUp(() => feed = fixture('html_in_plain_fields.xml'));

    test('decodes HTML entities the XML parser left alone', () {
      expect(feed.title, 'Ampersand & Co — The Show');
    });

    test('strips markup from an author inside CDATA', () {
      expect(feed.author, 'Jo & Ray');
    });

    test('strips markup from a title inside CDATA', () {
      expect(feed.items.first.title, 'Episode 1: Don’t Panic');
    });

    test('cannot recover markup that was escaped outside CDATA', () {
      // A known and unavoidable limit. `&lt;b&gt;` in an ordinary text node is
      // decoded to `<b>` by the XML parser before we ever see it, at which
      // point it is indistinguishable from a real tag and is stripped as one.
      // Inside CDATA nothing is decoded, so the same input survives — which is
      // why the test above passes and this one records a loss.
      expect(feed.items[1].title, 'Episode 2: not actually bold');
    });

    test('keeps the markup in a description', () {
      expect(feed.items[1].description, '<p>Line one.</p><p>Line two.</p>');
    });
  });

  test('reads itunes: elements whose prefix was never declared', () {
    // Malformed, and common enough that resolving namespaces strictly would
    // lose the duration on a large minority of real feeds.
    final feed = fixture('undeclared_namespaces.xml');
    expect(feed.author, 'Somebody');
    expect(feed.artworkUrl, Uri.parse('https://unbound.example/cover.png'));
    expect(feed.items.single.duration,
        const Duration(minutes: 44, seconds: 10));
  });

  group('items with no audio', () {
    late ParsedFeed feed;
    setUp(() => feed = fixture('unplayable_items.xml'));

    test('are dropped, with a warning naming each one', () {
      expect(feed.items.map((i) => i.title),
          ['Real Episode', 'Media Content Only']);
      expect(feed.warnings, hasLength(2));
      expect(feed.warnings.first, contains('Just a blog post'));
      expect(feed.warnings.last, contains('Enclosure With No URL'));
    });

    test('do not renumber the items that survive', () {
      // feedPosition is where the episode sits in the feed, not where it sits
      // in our list. Gaps are correct.
      expect(feed.items.map((i) => i.feedPosition), [1, 3]);
    });

    test('media:content is accepted where enclosure is absent', () {
      expect(feed.items.last.enclosureUrl,
          Uri.parse('https://mixed.example/media.m4a'));
    });
  });

  group('not a feed at all', () {
    test('truncated XML throws', () {
      expect(() => fixture('truncated.xml'),
          throwsA(isA<FeedFormatException>()));
    });

    test('an Atom feed throws, naming itself', () {
      expect(
        () => fixture('atom.xml'),
        throwsA(isA<FeedFormatException>()
            .having((e) => e.message, 'message', contains('Atom'))),
      );
    });

    test('well-formed XML that is not RSS throws', () {
      expect(() => parseFeed('<html><body>404</body></html>'),
          throwsA(isA<FeedFormatException>()));
    });
  });

  test('an empty but valid channel parses to a feed with no items', () {
    final feed = parseFeed(
        '<rss version="2.0"><channel><title>Nothing Yet</title></channel></rss>');
    expect(feed.title, 'Nothing Yet');
    expect(feed.items, isEmpty);
    expect(feed.warnings, isEmpty);
  });

  test('a channel with no title reports null rather than inventing one', () {
    // The parser does not know the feed URL. The caller does, and can fall
    // back to something meaningful.
    final feed = parseFeed('<rss version="2.0"><channel></channel></rss>');
    expect(feed.title, isNull);
  });
}
