import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../support.dart';

const feedUrl = 'https://feeds.example.com/show.xml';

String item({
  required String title,
  String? guid,
  String? url,
  String? date,
  String? duration,
}) =>
    '''
    <item>
      <title>$title</title>
      ${guid == null ? '' : '<guid>$guid</guid>'}
      ${date == null ? '' : '<pubDate>$date</pubDate>'}
      ${duration == null ? '' : '<itunes:duration>$duration</itunes:duration>'}
      <enclosure url="${url ?? 'https://cdn.example.com/$title.mp3'}"
                 type="audio/mpeg"/>
    </item>''';

String feed({
  String? title = 'The Cartographers',
  String? author,
  required List<String> items,
}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    ${title == null ? '' : '<title>$title</title>'}
    ${author == null ? '' : '<itunes:author>$author</itunes:author>'}
    ${items.join('\n')}
  </channel>
</rss>''';

/// Ids that a test can name.
String Function() counter(String prefix) {
  var next = 0;
  return () => '$prefix${next++}';
}

void main() {
  late CuesheetDatabase db;
  late FakeFeedTransport transport;
  late FeedIngestion ingestion;
  final at = DateTime.utc(2026, 8, 24, 9);

  void serve(String body, {String? etag}) {
    transport.bodies[feedUrl] = body;
    if (etag != null) transport.etags[feedUrl] = etag;
  }

  setUp(() {
    db = openTestDatabase();
    transport = FakeFeedTransport({}, etags: {});
    ingestion = FeedIngestion(
      db,
      transport: transport,
      clock: () => at,
      newEpisodeId: counter('e'),
      newPodcastId: counter('p'),
    );
  });

  tearDown(() => db.close());

  Future<List<EpisodeRow>> episodes() =>
      (db.select(db.episodes)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  Future<PodcastRow> podcast() => db.select(db.podcasts).getSingle();

  group('subscribing', () {
    test('creates the podcast and its episodes from one fetch', () async {
      serve(feed(author: 'Wren Alvarez', items: [
        item(title: 'One', guid: 'g1', date: 'Tue, 10 Jun 2025 09:00:00 GMT',
            duration: '14:30'),
        item(title: 'Two', guid: 'g2', date: 'Tue, 17 Jun 2025 09:00:00 GMT'),
      ]));

      final report = await ingestion.subscribe(Uri.parse(feedUrl));

      expect(report.podcastId, const PodcastId('p0'));
      expect(report.added, 2);
      expect(report.matched, 0);
      expect(report.rungs, {MatchRung.firstSighting: 2});

      final show = await podcast();
      expect(show.title, 'The Cartographers');
      expect(show.author, 'Wren Alvarez');
      expect(show.lastFetchedAt, at);

      final rows = await episodes();
      expect(rows.map((r) => r.title), ['One', 'Two']);
      expect(rows.first.durationMs, const Duration(minutes: 14, seconds: 30).inMilliseconds);
      expect(rows.first.publishedAt, DateTime.utc(2025, 6, 10, 9));
      expect(rows.every((r) => r.matchRung == MatchRung.firstSighting), isTrue);
    });

    test('subscribing to a feed already subscribed refreshes it', () async {
      serve(feed(items: [item(title: 'One', guid: 'g1')]));
      await ingestion.subscribe(Uri.parse(feedUrl));

      serve(feed(items: [
        item(title: 'One', guid: 'g1'),
        item(title: 'Two', guid: 'g2'),
      ]));
      final second = await ingestion.subscribe(Uri.parse(feedUrl));

      expect(second.podcastId, const PodcastId('p0'));
      expect(second.added, 1);
      expect(second.matched, 1);
      expect(await db.select(db.podcasts).get(), hasLength(1));
    });

    test('a URL that is not a feed leaves no subscription behind', () async {
      serve('<html><body>not a feed</body></html>');

      await expectLater(
        ingestion.subscribe(Uri.parse(feedUrl)),
        throwsA(isA<FeedFormatException>()),
      );
      expect(await db.select(db.podcasts).get(), isEmpty);
    });

    test('a URL that will not fetch leaves no subscription behind', () async {
      transport.failWith =
          const FeedTransportException('gone', statusCode: 410);

      await expectLater(
        ingestion.subscribe(Uri.parse(feedUrl)),
        throwsA(isA<FeedTransportException>()
            .having((e) => e.isPermanent, 'isPermanent', isTrue)),
      );
      expect(await db.select(db.podcasts).get(), isEmpty);
    });

    test('falls back to the host when the feed has no title', () async {
      serve(feed(title: null, items: [item(title: 'One', guid: 'g1')]));
      await ingestion.subscribe(Uri.parse(feedUrl));
      expect((await podcast()).title, 'feeds.example.com');
    });
  });

  group('conditional refresh', () {
    test('stores the validators and sends them back next time', () async {
      serve(feed(items: [item(title: 'One', guid: 'g1')]), etag: 'W/"abc"');
      await ingestion.subscribe(Uri.parse(feedUrl));

      expect((await podcast()).etag, 'W/"abc"');

      await ingestion.refresh(const PodcastId('p0'));
      expect(transport.requested.last.etag, 'W/"abc"');
    });

    test('a 304 changes nothing but the fetch timestamp', () async {
      serve(feed(items: [item(title: 'One', guid: 'g1')]), etag: 'W/"abc"');
      await ingestion.subscribe(Uri.parse(feedUrl));

      // A body that would wipe the library, which a 304 must stop us reading.
      serve(feed(items: []), etag: 'W/"abc"');

      final report = await ingestion.refresh(const PodcastId('p0'));
      expect(report.notModified, isTrue);
      expect(report.changedAnything, isFalse);
      expect(await episodes(), hasLength(1));
      expect((await podcast()).lastFetchedAt, at);
    });

    test('refreshing an unsubscribed id is an error, not a subscribe',
        () async {
      expect(() => ingestion.refresh(const PodcastId('nope')),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('re-ingesting a changed feed', () {
    test('an unchanged feed adds nothing and matches everything', () async {
      final body = feed(items: [
        item(title: 'One', guid: 'g1'),
        item(title: 'Two', guid: 'g2'),
      ]);
      serve(body);
      await ingestion.subscribe(Uri.parse(feedUrl));

      final report = await ingestion.refresh(const PodcastId('p0'));
      expect(report.added, 0);
      expect(report.matched, 2);
      expect(report.rungs, {MatchRung.guid: 2});
      expect(await episodes(), hasLength(2));
    });

    test('rewritten guids match on the enclosure URL and keep history',
        () async {
      serve(feed(items: [
        item(title: 'One', guid: 'old-1', url: 'https://cdn.example.com/1.mp3')
      ]));
      await ingestion.subscribe(Uri.parse(feedUrl));

      await DriftListeningRepository(db).save(ListeningState(
        episodeId: const EpisodeId('e0'),
        position: const Duration(minutes: 12),
        startCount: 1,
        lastPlayedAt: at,
      ));

      // Same audio, brand-new guid: a CMS migration.
      serve(feed(items: [
        item(title: 'One', guid: 'new-1', url: 'https://cdn.example.com/1.mp3')
      ]));
      final report = await ingestion.refresh(const PodcastId('p0'));

      expect(report.rungs, {MatchRung.enclosureUrl: 1});
      expect(await episodes(), hasLength(1));

      final row = (await episodes()).single;
      expect(row.id, 'e0');
      expect(row.guid, 'new-1');
      expect(row.matchRung, MatchRung.enclosureUrl);

      final listening =
          await DriftListeningRepository(db).byEpisode(const EpisodeId('e0'));
      expect(listening.position, const Duration(minutes: 12));
    });

    test('a tracking prefix appearing overnight is not a new episode',
        () async {
      serve(feed(items: [
        item(title: 'One', guid: 'g1', url: 'https://cdn.example.com/1.mp3')
      ]));
      await ingestion.subscribe(Uri.parse(feedUrl));

      serve(feed(items: [
        item(
            title: 'One',
            guid: 'g1',
            url: 'https://dts.podtrac.com/redirect.mp3/cdn.example.com/1.mp3')
      ]));
      await ingestion.refresh(const PodcastId('p0'));

      expect(await episodes(), hasLength(1));
    });

    test('surfaces the parser warnings on the report', () async {
      serve(feed(items: [
        item(title: 'One', guid: 'g1', date: 'sometime last Tuesday'),
        '<item><title>No Audio</title></item>',
      ]));
      final report = await ingestion.subscribe(Uri.parse(feedUrl));

      expect(report.warnings, hasLength(2));
      expect(report.warnings.any((w) => w.contains('last Tuesday')), isTrue);
      expect(report.warnings.any((w) => w.contains('No Audio')), isTrue);
    });
  });

  group('episodes that fall out of the feed', () {
    Future<void> subscribeToTwo() async {
      serve(feed(items: [
        item(title: 'One', guid: 'g1'),
        item(title: 'Two', guid: 'g2'),
      ]));
      await ingestion.subscribe(Uri.parse(feedUrl));
    }

    Future<IngestionReport> dropTheSecond() async {
      serve(feed(items: [item(title: 'One', guid: 'g1')]));
      return ingestion.refresh(const PodcastId('p0'));
    }

    test('an untouched one is deleted', () async {
      await subscribeToTwo();
      final report = await dropTheSecond();

      expect(report.deleted, 1);
      expect(report.orphaned, 0);
      expect((await episodes()).map((r) => r.id), ['e0']);
    });

    test('one with listening history is orphaned, never deleted', () async {
      await subscribeToTwo();
      await DriftListeningRepository(db).save(ListeningState(
        episodeId: const EpisodeId('e1'),
        position: const Duration(minutes: 3),
        startCount: 1,
        lastPlayedAt: at,
      ));

      final report = await dropTheSecond();
      expect(report.orphaned, 1);
      expect(report.deleted, 0);

      final row = (await episodes()).firstWhere((r) => r.id == 'e1');
      expect(row.isOrphaned, isTrue);
    });

    test('a blank listening row is not history', () async {
      // A row can exist with nothing in it. That is "not listened to", and
      // must not keep a vanished episode alive forever.
      await subscribeToTwo();
      await DriftListeningRepository(db)
          .save(const ListeningState(episodeId: EpisodeId('e1')));

      expect((await dropTheSecond()).deleted, 1);
    });

    test('one sitting in a cuesheet is orphaned', () async {
      // Otherwise a feed trimming its rolling window silently cascades an
      // item out of a saved queue — the exact loss this app refuses.
      await subscribeToTwo();
      await DriftCuesheetRepository(db, clock: () => at).save(Cuesheet(
        id: const CuesheetId('cs1'),
        kind: CuesheetKind.saved,
        title: 'Keepers',
        items: const [EpisodeId('e1')],
      ));

      final report = await dropTheSecond();
      expect(report.orphaned, 1);
      expect(report.deleted, 0);

      final items = await db.select(db.cuesheetItems).get();
      expect(items.map((i) => i.episodeId), ['e1']);
    });

    test('one the user filed under a category is orphaned', () async {
      await subscribeToTwo();
      await db.into(db.categories).insert(
          CategoriesCompanion.insert(id: 'news', name: 'News'));
      await db.into(db.episodeCategories).insert(
          EpisodeCategoriesCompanion.insert(
              episodeId: 'e1', categoryId: 'news'));

      expect((await dropTheSecond()).orphaned, 1);
    });

    test('an orphan the feed lists again is un-orphaned', () async {
      await subscribeToTwo();
      await DriftListeningRepository(db).save(ListeningState(
        episodeId: const EpisodeId('e1'),
        position: const Duration(minutes: 3),
        startCount: 1,
        lastPlayedAt: at,
      ));
      await dropTheSecond();

      serve(feed(items: [
        item(title: 'One', guid: 'g1'),
        item(title: 'Two', guid: 'g2'),
      ]));
      final report = await ingestion.refresh(const PodcastId('p0'));

      expect(report.unorphaned, 1);
      expect(report.added, 0);
      expect((await episodes()).every((r) => !r.isOrphaned), isTrue);
    });

    test('an episode already orphaned is not counted as orphaned again',
        () async {
      await subscribeToTwo();
      await DriftListeningRepository(db).save(ListeningState(
        episodeId: const EpisodeId('e1'),
        position: const Duration(minutes: 3),
        startCount: 1,
        lastPlayedAt: at,
      ));
      expect((await dropTheSecond()).orphaned, 1);
      expect((await dropTheSecond()).orphaned, 0);
    });
  });

  test('a feed that loses its title keeps the one it had', () async {
    serve(feed(items: [item(title: 'One', guid: 'g1')]));
    await ingestion.subscribe(Uri.parse(feedUrl));

    serve(feed(title: null, items: [item(title: 'One', guid: 'g1')]));
    await ingestion.refresh(const PodcastId('p0'));

    expect((await podcast()).title, 'The Cartographers');
  });

  test('generated ids are unique across a burst', () {
    // A four-hundred-episode feed is ingested well inside one millisecond.
    final ids = {for (var i = 0; i < 5000; i++) newLocalId('ep')};
    expect(ids, hasLength(5000));
  });
}
