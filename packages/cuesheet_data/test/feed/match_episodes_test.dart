import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:test/test.dart';

/// Deterministic ids, so a test can name the row it expects.
String Function() counter([String prefix = 'new']) {
  var next = 0;
  return () => '$prefix-${next++}';
}

ParsedItem item(
  String title, {
  String? guid,
  String? url,
  DateTime? publishedAt,
  int position = 0,
}) =>
    ParsedItem(
      title: title,
      guid: guid,
      enclosureUrl: Uri.parse(url ?? 'https://cdn.example.com/$title.mp3'),
      publishedAt: publishedAt,
      feedPosition: position,
    );

ExistingEpisode existing(
  String id, {
  String? guid,
  String url = 'https://cdn.example.com/a.mp3',
  String title = 'A',
  DateTime? publishedAt,
}) =>
    ExistingEpisode(
      id: EpisodeId(id),
      guid: guid,
      normalizedEnclosureUrl: normalizeEnclosureUrl(Uri.parse(url)),
      title: title,
      publishedAt: publishedAt,
    );

FeedMatch match(
  List<ExistingEpisode> rows,
  List<ParsedItem> items, {
  String Function()? ids,
}) =>
    matchFeedItems(
      existing: rows,
      incoming: items,
      newId: ids ?? counter(),
    );

void main() {
  group('rung 1: guid', () {
    test('matches on guid even when everything else has changed', () {
      final result = match(
        [existing('e1', guid: 'g1', url: 'https://old.example/a.mp3',
            title: 'Old Title', publishedAt: DateTime.utc(2025, 1, 1))],
        [item('Completely Renamed',
            guid: 'g1',
            url: 'https://new-cdn.example/b.mp3',
            publishedAt: DateTime.utc(2025, 6, 1))],
      );
      expect(result.items.single.id, const EpisodeId('e1'));
      expect(result.items.single.rung, MatchRung.guid);
      expect(result.vanished, isEmpty);
    });

    test('ignores whitespace around a guid on either side', () {
      final result = match(
        [existing('e1', guid: '  g1  ', url: 'https://x.example/1.mp3')],
        [item('A', guid: 'g1\n', url: 'https://y.example/2.mp3')],
      );
      expect(result.items.single.rung, MatchRung.guid);
    });

    test('an empty guid is not a guid, on either side', () {
      // Three episodes that all "have" guid "" must not collapse into one.
      final result = match(
        [existing('e1', guid: '', url: 'https://x.example/1.mp3')],
        [item('A', guid: '   ', url: 'https://y.example/2.mp3')],
      );
      expect(result.items.single.rung, MatchRung.firstSighting);
    });
  });

  group('rung 2: normalized enclosure URL', () {
    test('matches through a tracking prefix the feed has just added', () {
      final result = match(
        [existing('e1', url: 'https://cdn.example.com/a.mp3')],
        [
          item('A',
              url: 'https://dts.podtrac.com/redirect.mp3/'
                  'cdn.example.com/a.mp3?utm_source=rss')
        ],
      );
      expect(result.items.single.id, const EpisodeId('e1'));
      expect(result.items.single.rung, MatchRung.enclosureUrl);
    });

    test('is reached only when the guid rung misses', () {
      final result = match(
        [existing('e1', guid: 'g1', url: 'https://cdn.example.com/a.mp3')],
        [item('A', guid: 'g-different', url: 'https://cdn.example.com/a.mp3')],
      );
      expect(result.items.single.rung, MatchRung.enclosureUrl);
    });
  });

  group('rung 3: title and publication day', () {
    test('matches when the guid and the URL have both moved', () {
      final result = match(
        [
          existing('e1',
              guid: 'g1',
              url: 'https://old.example/a.mp3',
              title: 'The Mercator Problem',
              publishedAt: DateTime.utc(2025, 6, 10, 9))
        ],
        [
          item('the mercator problem',
              guid: 'g2',
              url: 'https://new.example/a.mp3',
              publishedAt: DateTime.utc(2025, 6, 10, 23, 45))
        ],
      );
      expect(result.items.single.id, const EpisodeId('e1'));
      expect(result.items.single.rung, MatchRung.titleAndDate);
    });

    test('does not match across a day boundary', () {
      final result = match(
        [existing('e1', title: 'A', publishedAt: DateTime.utc(2025, 6, 10),
            url: 'https://old.example/a.mp3')],
        [item('A', publishedAt: DateTime.utc(2025, 6, 11),
            url: 'https://new.example/a.mp3')],
      );
      expect(result.items.single.rung, MatchRung.firstSighting);
    });

    test('does not fire on title alone when there is no date', () {
      // "Episode 42", "Bonus" and "Introduction" recur. Matching on a title
      // with no date would hand one episode's history to another.
      final result = match(
        [existing('e1', title: 'Bonus', url: 'https://old.example/a.mp3')],
        [item('Bonus', url: 'https://new.example/a.mp3')],
      );
      expect(result.items.single.rung, MatchRung.firstSighting);
    });
  });

  group('claiming', () {
    test('two items cannot both take the same row', () {
      // A feed that republishes an episode under a new guid while leaving the
      // old item in place. Merging them would silently give one episode the
      // other's listening history.
      final result = match(
        [existing('e1', guid: 'g1', url: 'https://cdn.example.com/a.mp3')],
        [
          item('A', guid: 'g1', url: 'https://cdn.example.com/a.mp3'),
          item('A again', guid: 'g2', url: 'https://cdn.example.com/a.mp3'),
        ],
        ids: counter(),
      );
      expect(result.items[0].id, const EpisodeId('e1'));
      expect(result.items[0].rung, MatchRung.guid);
      expect(result.items[1].id, const EpisodeId('new-0'));
      expect(result.items[1].rung, MatchRung.firstSighting);
    });

    test('a claimed row does not block a lower rung from finding another', () {
      final result = match(
        [
          existing('e1', guid: 'g1', url: 'https://cdn.example.com/a.mp3'),
          existing('e2', guid: 'g2', url: 'https://cdn.example.com/a.mp3'),
        ],
        [
          item('A', guid: 'g1', url: 'https://cdn.example.com/a.mp3'),
          item('B', guid: 'unknown', url: 'https://cdn.example.com/a.mp3'),
        ],
      );
      expect(result.items[0].id, const EpisodeId('e1'));
      expect(result.items[1].id, const EpisodeId('e2'));
      expect(result.items[1].rung, MatchRung.enclosureUrl);
      expect(result.vanished, isEmpty);
    });
  });

  group('new and vanished', () {
    test('an unmatched item gets a fresh id and says it is a first sighting',
        () {
      final result = match([], [item('A'), item('B')], ids: counter('id'));
      expect(result.items.map((m) => m.id.value), ['id-0', 'id-1']);
      expect(result.items.every((m) => m.isNew), isTrue);
      expect(result.newEpisodes, hasLength(2));
    });

    test('a row the feed no longer mentions is reported as vanished', () {
      final result = match(
        [
          existing('e1', guid: 'g1', url: 'https://x.example/1.mp3'),
          existing('e2', guid: 'g2', url: 'https://x.example/2.mp3'),
        ],
        [item('A', guid: 'g1', url: 'https://x.example/1.mp3')],
      );
      expect(result.vanished, [const EpisodeId('e2')]);
    });

    test('an empty feed vanishes everything and matches nothing', () {
      final result = match([existing('e1', guid: 'g1')], []);
      expect(result.items, isEmpty);
      expect(result.vanished, [const EpisodeId('e1')]);
    });
  });

  test('re-running against its own output is a no-op', () {
    // The property that matters: a refresh that changed nothing must produce
    // no new ids and no vanished rows, or every refresh churns the library.
    final items = [
      item('A', guid: 'g1', url: 'https://x.example/1.mp3',
          publishedAt: DateTime.utc(2025, 1, 1)),
      item('B', url: 'https://x.example/2.mp3',
          publishedAt: DateTime.utc(2025, 1, 8)),
      item('C', url: 'https://x.example/3.mp3'),
    ];
    final first = match([], items, ids: counter());

    final rows = [
      for (final m in first.items)
        ExistingEpisode(
          id: m.id,
          guid: m.item.guid,
          normalizedEnclosureUrl: normalizeEnclosureUrl(m.item.enclosureUrl),
          title: m.item.title,
          publishedAt: m.item.publishedAt,
        ),
    ];

    final second = match(rows, items, ids: counter('should-not-be-used'));
    expect(second.items.map((m) => m.id), first.items.map((m) => m.id));
    expect(second.items.map((m) => m.isNew), everyElement(isFalse));
    expect(second.vanished, isEmpty);
  });
}
