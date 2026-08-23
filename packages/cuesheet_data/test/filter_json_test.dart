import 'dart:convert';

import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:test/test.dart';

import 'support.dart';

EpisodeFilter roundTrip(EpisodeFilter filter) => decodeFilter(
    jsonDecode(jsonEncode(encodeFilter(filter))) as Map<String, Object?>);

void main() {
  /// One of each variant. Adding a variant to the union breaks `encodeFilter`
  /// at compile time, so this list only has to stay representative, not
  /// exhaustive-by-construction.
  final variants = <String, EpisodeFilter>{
    'listenState': const ListenStateIs(
        {ListenState.unplayed, ListenState.relistenCandidate}),
    'inPodcasts': const InPodcasts({PodcastId('p1'), PodcastId('p2')}),
    'inCategories': const InCategories({CategoryId('news')}),
    'duration both bounds': const DurationBetween(
        min: Duration(minutes: 5), max: Duration(minutes: 90)),
    'duration one bound': const DurationBetween(max: Duration(minutes: 90)),
    'duration no bounds': const DurationBetween(),
    'published': PublishedBetween(
        from: DateTime.utc(2026, 1, 1), to: DateTime.utc(2026, 12, 31)),
    'lastPlayed': LastPlayedBetween(from: DateTime.utc(2025, 6, 1)),
    'playCount': const PlayCountBetween(min: 1, max: 5),
    'title': const TitleContains('the rest is'),
    'allOf empty': const AllOf([]),
    'anyOf empty': const AnyOf([]),
    'not': const Not(TitleContains('x')),
    'nested': const AllOf([
      InPodcasts({PodcastId('p1')}),
      AnyOf([
        ListenStateIs({ListenState.started}),
        Not(InCategories({CategoryId('fiction')})),
      ]),
      DurationBetween(max: Duration(minutes: 30)),
    ]),
  };

  group('filters round-trip', () {
    for (final MapEntry(key: name, value: filter) in variants.entries) {
      test(name, () => expect(roundTrip(filter), filter));
    }

    test('preserves UTC rather than drifting to local time', () {
      final at = DateTime.utc(2026, 3, 4, 5, 6, 7, 890);
      final decoded = roundTrip(PublishedBetween(from: at)) as PublishedBetween;

      expect(decoded.from, at);
      expect(decoded.from!.isUtc, isTrue);
    });

    test('a decoded filter selects exactly what the original did', () async {
      // Structural equality is the stronger claim, but this is the one that
      // actually matters: a saved smart list must keep meaning the same thing.
      final db = openTestDatabase();
      addTearDown(db.close);
      await seed(db);
      final corpus = await DriftEpisodeRepository(db, clock: () => now)
          .find(const EpisodeQuery(sort: []));

      for (final filter in variants.values) {
        Set<String> select(EpisodeFilter f) => {
              for (final v in corpus)
                if (matchesFilter(f, v, now: now)) v.episode.id.value,
            };

        expect(select(roundTrip(filter)), select(filter),
            reason: 'disagreement after round-tripping $filter');
      }
    });
  });

  group('sorting round-trips', () {
    test('every field, both directions', () {
      final sort = [
        for (final field in SortField.values) ...[
          SortSpec(field),
          SortSpec(field, descending: true),
        ],
      ];

      expect(decodeSort(jsonDecode(jsonEncode(encodeSort(sort))) as List<Object?>),
          sort);
    });

    test('a whole query round-trips', () {
      const query = EpisodeQuery(
        filter: AllOf([
          InPodcasts({PodcastId('p1')}),
          PlayCountBetween(max: 0),
        ]),
        sort: [
          SortSpec(SortField.lastPlayedAt, descending: true),
          SortSpec(SortField.publishedAt),
        ],
      );
      final encoded = encodeQuery(query);

      expect(
        decodeQuery(
            filterJson: encoded.filterJson, sortJson: encoded.sortJson),
        query,
      );
    });
  });

  group('malformed input fails loudly', () {
    test('unknown filter type', () {
      expect(() => decodeFilter(const {'type': 'telepathy'}),
          throwsFormatException);
    });

    test('unknown listen state', () {
      expect(
        () => decodeFilter(const {
          'type': 'listenState',
          'states': ['bewildered'],
        }),
        throwsFormatException,
      );
    });

    test('unknown sort field', () {
      expect(
        () => decodeSort(const [
          {'field': 'vibes', 'descending': false}
        ]),
        throwsFormatException,
      );
    });

    test('a list where a list was promised', () {
      expect(
        () => decodeFilter(const {'type': 'inPodcasts', 'ids': 'p1'}),
        throwsFormatException,
      );
    });
  });

  group('SavedFilterRepository', () {
    late CuesheetDatabase db;
    late DriftSavedFilterRepository filters;

    setUp(() async {
      db = openTestDatabase();
      await seed(db);
      filters = DriftSavedFilterRepository(db);
    });

    tearDown(() async => db.close());

    test('round-trips a smart list through the database', () async {
      const saved = SavedFilter(
        id: SavedFilterId('sf1'),
        name: 'Short and unheard',
        query: EpisodeQuery(
          filter: AllOf([
            ListenStateIs({ListenState.unplayed}),
            DurationBetween(max: Duration(minutes: 30)),
          ]),
          sort: [SortSpec(SortField.publishedAt, descending: true)],
        ),
      );
      await filters.upsert(saved);

      expect(await filters.byId(const SavedFilterId('sf1')), saved);
    });

    test('a stored smart list still selects the right episodes', () async {
      // End to end: define a list, store it, read it back, run it as SQL.
      const saved = SavedFilter(
        id: SavedFilterId('sf1'),
        name: 'Relisten pile',
        query: EpisodeQuery(
            filter: ListenStateIs({ListenState.relistenCandidate})),
      );
      await filters.upsert(saved);

      final reloaded = (await filters.byId(const SavedFilterId('sf1')))!;
      final results = await DriftEpisodeRepository(db, clock: () => now)
          .find(reloaded.query);

      expect([for (final v in results) v.episode.id.value], ['e4']);
    });

    test('upsert replaces rather than duplicating', () async {
      const first = SavedFilter(
        id: SavedFilterId('sf1'),
        name: 'First name',
        query: EpisodeQuery(),
      );
      await filters.upsert(first);
      await filters.upsert(first.copyWith(name: 'Second name'));

      final all = await filters.watchAll().first;
      expect(all, hasLength(1));
      expect(all.single.name, 'Second name');
    });

    test('lists alphabetically', () async {
      for (final name in ['Zebra', 'Apple', 'Mango']) {
        await filters.upsert(SavedFilter(
          id: SavedFilterId(name),
          name: name,
          query: const EpisodeQuery(),
        ));
      }

      expect([for (final f in await filters.watchAll().first) f.name],
          ['Apple', 'Mango', 'Zebra']);
    });
  });
}
