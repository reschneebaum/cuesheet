import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late CuesheetDatabase db;
  late DriftPodcastRepository podcasts;
  late DriftEpisodeRepository episodes;
  late DriftListeningRepository listening;

  setUp(() async {
    db = openTestDatabase();
    await seed(db);
    podcasts = DriftPodcastRepository(db);
    episodes = DriftEpisodeRepository(db, clock: () => now);
    listening = DriftListeningRepository(db);
  });

  tearDown(() async => db.close());

  group('schema', () {
    test('enforces foreign keys', () async {
      // Off by default in SQLite, per connection. The beforeOpen pragma is
      // what makes the `references` declarations mean anything.
      expect(
        () => db.into(db.episodes).insert(EpisodesCompanion.insert(
              id: 'orphan',
              podcastId: 'no-such-podcast',
              enclosureUrl: 'https://x/a.mp3',
              normalizedEnclosureUrl: 'https://x/a.mp3',
              title: 'Orphan',
            )),
        throwsA(isA<SqliteException>()),
      );
    });

    test('cascades a podcast deletion through episodes and listening state',
        () async {
      await podcasts.remove(const PodcastId('p1'));

      final remaining = await episodes.find(const EpisodeQuery());
      expect(remaining.map((v) => v.episode.podcastId.value).toSet(), {'p2'});

      final orphanedState = await db.select(db.listeningStates).get();
      expect(orphanedState.map((r) => r.episodeId), isNot(contains('e3')));
    });

    test('rejects a duplicate feed URL', () async {
      expect(
        () => podcasts.upsert(Podcast(
          id: const PodcastId('p3'),
          feedUrl: Uri.parse('https://example.com/one.xml'),
          title: 'Impostor',
        )),
        throwsA(isA<SqliteException>()),
      );
    });

    test('stores the normalized enclosure URL alongside the original',
        () async {
      await episodes.upsertAll([
        Episode(
          id: const EpisodeId('wrapped'),
          podcastId: const PodcastId('p1'),
          title: 'Wrapped',
          enclosureUrl: Uri.parse(
              'https://dts.podtrac.com/redirect.mp3/cdn.example.com/w.mp3'),
        ),
      ]);

      final row = await (db.select(db.episodes)
            ..where((t) => t.id.equals('wrapped')))
          .getSingle();

      expect(row.enclosureUrl, contains('podtrac'));
      expect(row.normalizedEnclosureUrl, 'https://cdn.example.com/w.mp3');
    });
  });

  group('ListeningRepository', () {
    test('returns a blank state for an episode nobody has touched', () async {
      final state = await listening.byEpisode(const EpisodeId('e1'));

      expect(state.position, Duration.zero);
      expect(state.playCount, 0);
      expect(state.lastPlayedAt, isNull);
    });

    test('round-trips everything the domain cares about', () async {
      final saved = ListeningState(
        episodeId: const EpisodeId('e1'),
        position: const Duration(minutes: 12, seconds: 34),
        playCount: 3,
        startCount: 4,
        firstPlayedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        lastPlayedAt: DateTime.utc(2026, 5, 6, 7, 8, 9),
        finishedAt: DateTime.utc(2026, 5, 6, 7, 8, 9),
        explicitlyFinished: true,
        countedThisSession: true,
      );
      await listening.save(saved);

      expect(await listening.byEpisode(const EpisodeId('e1')), saved);
    });

    test('preserves sub-second timestamps', () async {
      // Drift's default timestamp storage truncates to whole seconds, which
      // would silently disagree with the domain about relisten staleness.
      final at = DateTime.utc(2026, 5, 6, 7, 8, 9, 123);
      await listening.save(
          ListeningState(episodeId: const EpisodeId('e1'), lastPlayedAt: at));

      final read = await listening.byEpisode(const EpisodeId('e1'));
      expect(read.lastPlayedAt, at);
    });
  });

  group('EpisodeRepository', () {
    test('assembles an episode with its podcast title and categories',
        () async {
      final view = await episodes.byId(const EpisodeId('e8'));

      expect(view, isNotNull);
      expect(view!.episode.title, 'theta');
      expect(view.podcastTitle, 'Another Show');
      expect(view.categories.map((c) => c.value),
          unorderedEquals(['news', 'fiction']));
    });

    test('returns null for an episode that does not exist', () async {
      expect(await episodes.byId(const EpisodeId('nope')), isNull);
    });

    test('upsertAll updates rather than duplicating', () async {
      final before = await episodes.find(const EpisodeQuery());
      await episodes.upsertAll([
        Episode(
          id: const EpisodeId('e1'),
          podcastId: const PodcastId('p1'),
          title: 'Alpha, revised',
          enclosureUrl: Uri.parse('https://cdn.example.com/e1.mp3'),
        ),
      ]);
      final after = await episodes.find(const EpisodeQuery());

      expect(after, hasLength(before.length));
      expect((await episodes.byId(const EpisodeId('e1')))!.episode.title,
          'Alpha, revised');
    });

    test('a feed rewrite does not touch listening history', () async {
      // The reason Episode and ListeningState are separate tables at all.
      final before = await listening.byEpisode(const EpisodeId('e3'));
      await episodes.upsertAll([
        Episode(
          id: const EpisodeId('e3'),
          podcastId: const PodcastId('p1'),
          title: 'Gamma, re-published with a new GUID',
          enclosureUrl: Uri.parse('https://cdn.example.com/e3-v2.mp3'),
          guid: 'brand-new-guid',
        ),
      ]);

      expect(await listening.byEpisode(const EpisodeId('e3')), before);
    });

    test('honours limit', () async {
      final some = await episodes.find(const EpisodeQuery(limit: 3));
      expect(some, hasLength(3));
    });

    test('watch re-emits when the underlying data changes', () async {
      final seen = <int>[];
      final sub =
          episodes.watch(const EpisodeQuery()).listen((v) => seen.add(v.length));
      await pumpEventQueue();

      await episodes.upsertAll([
        Episode(
          id: const EpisodeId('e9'),
          podcastId: const PodcastId('p1'),
          title: 'Iota',
          enclosureUrl: Uri.parse('https://cdn.example.com/e9.mp3'),
        ),
      ]);
      await pumpEventQueue();
      await sub.cancel();

      expect(seen, [8, 9]);
    });
  });
}
