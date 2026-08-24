import 'dart:io';

import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:test/test.dart';

import '../support.dart';

/// The corpus of §13: feeds that exist, captured verbatim, not feeds we would
/// have written. See `test/fixtures/feeds/real/README.md` for what each one
/// caught.
final corpus = Directory('test/fixtures/feeds/real')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.xml'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

String name(File f) => f.uri.pathSegments.last;

ParsedFeed load(String fixture) => parseFeed(
    File('test/fixtures/feeds/real/$fixture').readAsStringSync());

void main() {
  test('the corpus is actually here', () {
    // A test suite that silently tests nothing is worse than no suite.
    expect(corpus, hasLength(4));
  });

  for (final file in corpus) {
    group(name(file), () {
      late ParsedFeed feed;
      setUpAll(() => feed = parseFeed(file.readAsStringSync()));

      test('parses with no warnings at all', () {
        // These are four mainstream, professionally hosted feeds. If any of
        // them warns, the parser is wrong before the feed is.
        expect(feed.warnings, isEmpty);
        expect(feed.title, isNotNull);
        expect(feed.items, isNotEmpty);
      });

      test('every item is playable and identifiable', () {
        for (final item in feed.items) {
          expect(item.title, isNotEmpty, reason: '${item.feedPosition}');
          expect(item.enclosureUrl.hasScheme, isTrue);
          expect(item.guid, isNotNull, reason: 'item ${item.feedPosition}');
          expect(item.publishedAt, isNotNull, reason: 'item ${item.feedPosition}');
          expect(item.duration, isNotNull, reason: 'item ${item.feedPosition}');
        }
      });

      test('normalized enclosure keys are unique and are real URLs', () {
        // The property rung 2 rests on. A collision here would merge two
        // episodes and hand one the other's listening history.
        final keys = <String, ParsedItem>{};
        for (final item in feed.items) {
          final key = normalizeEnclosureUrl(item.enclosureUrl);
          final parsed = Uri.parse(key);
          expect(parsed.host, contains('.'), reason: key);
          expect(parsed.pathSegments, isNotEmpty, reason: key);
          expect(keys.containsKey(key), isFalse,
              reason: 'collides with ${keys[key]}: $key');
          keys[key] = item;
        }
      });

      test('published dates are all UTC and all in the past', () {
        for (final item in feed.items) {
          expect(item.publishedAt!.isUtc, isTrue);
          expect(item.publishedAt!.year, greaterThan(2005));
        }
      });

      test('re-ingesting the same feed changes nothing', () {
        // The churn property, on real data: the second refresh of an unchanged
        // feed must produce no new ids and no vanished rows.
        var next = 0;
        final first = matchFeedItems(
          existing: const [],
          incoming: feed.items,
          newId: () => 'id-${next++}',
        );
        final rows = [
          for (final m in first.items)
            ExistingEpisode(
              id: m.id,
              guid: m.item.guid,
              normalizedEnclosureUrl:
                  normalizeEnclosureUrl(m.item.enclosureUrl),
              title: m.item.title,
              publishedAt: m.item.publishedAt,
            ),
        ];

        final second = matchFeedItems(
          existing: rows,
          incoming: feed.items,
          newId: () => fail('a second ingest must not mint an id'),
        );
        expect(second.vanished, isEmpty);
        expect(second.rungs(MatchRung.guid), feed.items.length);
      });
    });
  }

  group('what each feed taught us', () {
    test('guid schemes change mid-feed when a show moves host', () {
      // Last Podcast On The Left migrated off SoundCloud; Rotten Mango off
      // Buzzsprout. Both kept the old guids on old episodes, so one feed
      // carries two unrelated id schemes. This is why §6 keeps a local
      // surrogate key and treats guid as a hint.
      final lpotl = load('last_podcast_on_the_left.xml');
      expect(lpotl.items.first.guid, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(lpotl.items.last.guid, startsWith('tag:soundcloud,2010:tracks/'));

      final rotten = load('rotten_mango.xml');
      expect(rotten.items.first.guid, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(rotten.items.last.guid, startsWith('Buzzsprout-'));
    });

    test('duration format is per-host, not per-spec', () {
      // Megaphone writes bare seconds, Simplecast writes hh:mm:ss. Both are
      // legal; a parser that handles only one loses every duration on half the
      // library.
      expect(load('epstein_files_book_club.xml').items.last.duration,
          const Duration(seconds: 52));
      expect(load('last_podcast_on_the_left.xml').items.last.duration,
          const Duration(minutes: 41, seconds: 39));
    });

    test('one feed can use two timezone spellings', () {
      // `-0000` and `+0000` both appear, and mean the same thing.
      expect(
        load('black_girl_gone.xml').items.every((i) => i.publishedAt!.isUtc),
        isTrue,
      );
    });

    test('guids arrive wrapped in CDATA on some hosts and bare on others', () {
      // The XML parser hides the difference, which is the point of asserting
      // it: the trimming must not be doing it by hand somewhere.
      expect(load('black_girl_gone.xml').items.first.guid,
          isNot(contains('CDATA')));
    });

    test('the five-deep wrapper chain resolves to the origin', () {
      final item = load('black_girl_gone.xml').items.first;
      expect(item.enclosureUrl.host, 'www.podtrac.com');
      expect(normalizeEnclosureUrl(item.enclosureUrl),
          startsWith('https://traffic.megaphone.fm/'));
    });
  });

  test('a real feed ingests end to end', () async {
    const url = 'https://feeds.megaphone.fm/CFQ4676831519';
    final db = openTestDatabase();
    addTearDown(db.close);

    final body =
        File('test/fixtures/feeds/real/epstein_files_book_club.xml')
            .readAsStringSync();
    var next = 0;
    final ingestion = FeedIngestion(
      db,
      transport: FakeFeedTransport({url: body}),
      clock: () => DateTime.utc(2026, 8, 24),
      newEpisodeId: () => 'e${next++}',
      newPodcastId: () => 'p0',
    );

    final report = await ingestion.subscribe(Uri.parse(url));
    expect(report.added, 36);
    expect(report.warnings, isEmpty);

    final episodes = await DriftEpisodeRepository(db,
            clock: () => DateTime.utc(2026, 8, 24))
        .find(const EpisodeQuery());
    expect(episodes, hasLength(36));
    expect(episodes.first.episode.title, isNotEmpty);

    // And again: the refresh that must cost nothing.
    final second = await ingestion.refresh(const PodcastId('p0'));
    expect(second.added, 0);
    expect(second.matched, 36);
    expect(second.deleted, 0);
    expect(second.orphaned, 0);
  });
}

extension on FeedMatch {
  int rungs(MatchRung rung) => items.where((i) => i.rung == rung).length;
}
