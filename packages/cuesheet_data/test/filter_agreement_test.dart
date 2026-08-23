import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The SQL compiler and the domain's `matchesFilter` are two implementations
/// of one specification. These tests are what keep them honest.
void main() {
  late CuesheetDatabase db;
  late DriftEpisodeRepository episodes;
  late List<EpisodeView> corpus;

  setUp(() async {
    db = openTestDatabase();
    await seed(db);
    episodes = DriftEpisodeRepository(db, clock: () => now);
    // Read the corpus back through the same mapping the queries use, so any
    // disagreement can only come from filter semantics, never from the data.
    corpus = await episodes.find(const EpisodeQuery(sort: []));
  });

  tearDown(() async => db.close());

  test('the corpus covers every listen state', () {
    // Without this, an agreement test comparing two empty sets passes while
    // proving nothing.
    final states = {
      for (final v in corpus)
        listenStateOf(v.listening,
            episodeDuration: v.episode.duration, now: now)
    };
    expect(states, containsAll(ListenState.values));
    expect(corpus, hasLength(8));
  });

  group('filters agree with the domain', () {
    final filters = <String, EpisodeFilter>{
      'everything': const AllOf([]),
      'nothing': const AnyOf([]),
      for (final s in ListenState.values) 'state ${s.name}': ListenStateIs({s}),
      'state unplayed or started':
          const ListenStateIs({ListenState.unplayed, ListenState.started}),
      'state none': const ListenStateIs({}),
      'podcast p1': const InPodcasts({PodcastId('p1')}),
      'podcast p2': const InPodcasts({PodcastId('p2')}),
      'podcast none': const InPodcasts({}),
      'podcast unknown': const InPodcasts({PodcastId('nope')}),
      'category news': const InCategories({CategoryId('news')}),
      'category fiction': const InCategories({CategoryId('fiction')}),
      'category both':
          const InCategories({CategoryId('news'), CategoryId('fiction')}),
      'category none': const InCategories({}),
      'duration under 30m': const DurationBetween(max: Duration(minutes: 30)),
      'duration over 30m': const DurationBetween(min: Duration(minutes: 30)),
      'duration 1s to 1m': const DurationBetween(
          min: Duration(seconds: 1), max: Duration(minutes: 1)),
      'published in 2026 Q1': PublishedBetween(
          from: DateTime.utc(2026, 1, 1), to: DateTime.utc(2026, 3, 31)),
      'published after March': PublishedBetween(from: DateTime.utc(2026, 3, 2)),
      'played in the last week':
          LastPlayedBetween(from: now.subtract(const Duration(days: 7))),
      'played more than 100 days ago':
          LastPlayedBetween(to: now.subtract(const Duration(days: 100))),
      'never finished': const PlayCountBetween(max: 0),
      'finished at least twice': const PlayCountBetween(min: 2),
      'title contains a': const TitleContains('a'),
      'title contains ALPHA (case)': const TitleContains('ALPHA'),
      'title contains a LIKE wildcard': const TitleContains('50%'),
      'title contains an underscore wildcard': const TitleContains('_'),
      'title matches nothing': const TitleContains('zzzzz'),
      'not p1': const Not(InPodcasts({PodcastId('p1')})),
      'not unplayed': const Not(ListenStateIs({ListenState.unplayed})),
      'p1 and unplayed': const AllOf([
        InPodcasts({PodcastId('p1')}),
        ListenStateIs({ListenState.unplayed}),
      ]),
      'p2 or news': const AnyOf([
        InPodcasts({PodcastId('p2')}),
        InCategories({CategoryId('news')}),
      ]),
      'a real smart list': const AllOf([
        ListenStateIs({ListenState.unplayed, ListenState.started}),
        DurationBetween(max: Duration(minutes: 30)),
        Not(InCategories({CategoryId('fiction')})),
      ]),
      'deeply nested': const AllOf([
        AnyOf([
          AllOf([
            InPodcasts({PodcastId('p1')}),
            Not(ListenStateIs({ListenState.finished})),
          ]),
          InCategories({CategoryId('fiction')}),
        ]),
        Not(TitleContains('zeta')),
      ]),
    };

    for (final MapEntry(key: name, value: filter) in filters.entries) {
      test(name, () async {
        final fromSql = (await episodes
                .find(EpisodeQuery(filter: filter, sort: const [])))
            .map((v) => v.episode.id.value)
            .toSet();
        final fromDomain = corpus
            .where((v) => matchesFilter(filter, v, now: now))
            .map((v) => v.episode.id.value)
            .toSet();

        expect(fromSql, fromDomain);
      });
    }
  });

  group('ordering agrees with the domain', () {
    for (final field in SortField.values) {
      for (final descending in [false, true]) {
        test('${field.name} ${descending ? 'descending' : 'ascending'}',
            () async {
          final sort = [SortSpec(field, descending: descending)];

          final fromSql = (await episodes.find(EpisodeQuery(sort: sort)))
              .map((v) => v.episode.id.value)
              .toList();
          final fromDomain = ([...corpus]
                ..sort((a, b) => compareEpisodes(sort, a, b)))
              .map((v) => v.episode.id.value)
              .toList();

          expect(fromSql, fromDomain);
        });
      }
    }

    test('multi-key ordering agrees too', () async {
      const sort = [
        SortSpec(SortField.playCount, descending: true),
        SortSpec(SortField.publishedAt),
      ];

      final fromSql = (await episodes.find(const EpisodeQuery(sort: sort)))
          .map((v) => v.episode.id.value)
          .toList();
      final fromDomain =
          ([...corpus]..sort((a, b) => compareEpisodes(sort, a, b)))
              .map((v) => v.episode.id.value)
              .toList();

      expect(fromSql, fromDomain);
    });
  });
}
