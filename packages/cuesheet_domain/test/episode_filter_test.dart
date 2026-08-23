import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 6, 1, 12);

EpisodeView view({
  String id = 'e1',
  String podcast = 'p1',
  String title = 'An Episode',
  String podcastTitle = 'A Show',
  Duration? duration = const Duration(minutes: 60),
  DateTime? publishedAt,
  int? feedPosition,
  Set<String> categories = const {},
  Duration position = Duration.zero,
  int playCount = 0,
  DateTime? lastPlayedAt,
  DateTime? firstPlayedAt,
  bool explicitlyFinished = false,
}) =>
    EpisodeView(
      episode: Episode(
        id: EpisodeId(id),
        podcastId: PodcastId(podcast),
        title: title,
        enclosureUrl: Uri.parse('https://example.com/$id.mp3'),
        duration: duration,
        publishedAt: publishedAt,
        feedPosition: feedPosition,
      ),
      listening: ListeningState(
        episodeId: EpisodeId(id),
        position: position,
        playCount: playCount,
        lastPlayedAt: lastPlayedAt,
        firstPlayedAt: firstPlayedAt,
        explicitlyFinished: explicitlyFinished,
      ),
      podcastTitle: podcastTitle,
      categories: categories.map(CategoryId.new).toSet(),
    );

bool matches(EpisodeFilter f, EpisodeView v) =>
    matchesFilter(f, v, now: t0);

void main() {
  group('ListenStateIs', () {
    test('selects unplayed', () {
      expect(matches(const ListenStateIs({ListenState.unplayed}), view()), isTrue);
    });

    test('selects started', () {
      final v = view(position: const Duration(minutes: 10));
      expect(matches(const ListenStateIs({ListenState.started}), v), isTrue);
      expect(matches(const ListenStateIs({ListenState.unplayed}), v), isFalse);
    });

    test('selects relisten candidates', () {
      final v = view(
        position: const Duration(minutes: 59, seconds: 45),
        playCount: 1,
        lastPlayedAt: t0.subtract(const Duration(days: 200)),
      );
      expect(matches(const ListenStateIs({ListenState.relistenCandidate}), v),
          isTrue);
      // A relisten candidate is not also plainly "finished" — the states are
      // exclusive, so a filter must name the one it wants.
      expect(matches(const ListenStateIs({ListenState.finished}), v), isFalse);
    });

    test('accepts a set of states', () {
      final v = view(position: const Duration(minutes: 10));
      expect(
        matches(
            const ListenStateIs({ListenState.unplayed, ListenState.started}), v),
        isTrue,
      );
    });
  });

  group('scalar predicates', () {
    test('InPodcasts', () {
      expect(matches(const InPodcasts({PodcastId('p1')}), view()), isTrue);
      expect(matches(const InPodcasts({PodcastId('other')}), view()), isFalse);
    });

    test('InCategories matches on any overlap', () {
      final v = view(categories: {'news', 'daily'});
      expect(matches(const InCategories({CategoryId('daily')}), v), isTrue);
      expect(matches(const InCategories({CategoryId('fiction')}), v), isFalse);
    });

    test('DurationBetween is inclusive on both ends', () {
      final v = view(duration: const Duration(minutes: 30));
      expect(
          matches(
              const DurationBetween(min: Duration(minutes: 30)), v), isTrue);
      expect(
          matches(
              const DurationBetween(max: Duration(minutes: 30)), v), isTrue);
      expect(
          matches(
              const DurationBetween(min: Duration(minutes: 31)), v), isFalse);
    });

    test('DurationBetween excludes episodes with no known duration', () {
      // Unknown is not zero and not infinity — it simply cannot satisfy a
      // range, in either direction.
      final v = view(duration: null);
      expect(matches(const DurationBetween(max: Duration(days: 1)), v), isFalse);
    });

    test('PublishedBetween is inclusive and excludes unknown dates', () {
      final at = DateTime.utc(2026, 3, 1);
      expect(matches(PublishedBetween(from: at), view(publishedAt: at)), isTrue);
      expect(matches(PublishedBetween(to: at), view(publishedAt: at)), isTrue);
      expect(matches(PublishedBetween(from: at), view(publishedAt: null)), isFalse);
    });

    test('LastPlayedBetween excludes never-played episodes', () {
      expect(
        matches(LastPlayedBetween(from: t0.subtract(const Duration(days: 7))),
            view()),
        isFalse,
      );
    });

    test('PlayCountBetween', () {
      expect(matches(const PlayCountBetween(min: 1), view(playCount: 2)), isTrue);
      expect(matches(const PlayCountBetween(min: 1), view()), isFalse);
      expect(matches(const PlayCountBetween(max: 0), view()), isTrue);
    });

    test('TitleContains ignores case', () {
      final v = view(title: 'The Rest Is History');
      expect(matches(const TitleContains('rest is'), v), isTrue);
      expect(matches(const TitleContains('REST'), v), isTrue);
      expect(matches(const TitleContains('politics'), v), isFalse);
    });
  });

  group('combinators', () {
    test('AllOf is vacuously true when empty', () {
      expect(matches(const AllOf([]), view()), isTrue);
    });

    test('AnyOf is vacuously false when empty', () {
      expect(matches(const AnyOf([]), view()), isFalse);
    });

    test('Not inverts', () {
      expect(matches(const Not(InPodcasts({PodcastId('p1')})), view()), isFalse);
    });

    test('nests to arbitrary depth', () {
      final v = view(position: const Duration(minutes: 10), categories: {'news'});
      final filter = AllOf([
        const ListenStateIs({ListenState.started}),
        AnyOf([
          const InCategories({CategoryId('fiction')}),
          const InCategories({CategoryId('news')}),
        ]),
        const Not(PlayCountBetween(min: 1)),
      ]);

      expect(matches(filter, v), isTrue);
    });

    test('a realistic smart list: unfinished short episodes from one show', () {
      final filter = AllOf([
        const InPodcasts({PodcastId('p1')}),
        const ListenStateIs({ListenState.unplayed, ListenState.started}),
        const DurationBetween(max: Duration(minutes: 30)),
      ]);

      expect(matches(filter, view(duration: const Duration(minutes: 20))), isTrue);
      expect(matches(filter, view(duration: const Duration(minutes: 90))), isFalse);
      expect(
        matches(filter, view(duration: const Duration(minutes: 20), playCount: 1,
            position: const Duration(minutes: 59, seconds: 59))),
        isFalse,
      );
    });
  });

  group('compareEpisodes', () {
    final jan = DateTime.utc(2026, 1, 1);
    final feb = DateTime.utc(2026, 2, 1);

    test('sorts ascending by default', () {
      final a = view(id: 'a', publishedAt: jan);
      final b = view(id: 'b', publishedAt: feb);

      expect(compareEpisodes(const [SortSpec(SortField.publishedAt)], a, b),
          lessThan(0));
    });

    test('descending flips the comparison', () {
      final a = view(id: 'a', publishedAt: jan);
      final b = view(id: 'b', publishedAt: feb);

      expect(
        compareEpisodes(
            const [SortSpec(SortField.publishedAt, descending: true)], a, b),
        greaterThan(0),
      );
    });

    test('missing values sort last, ascending AND descending', () {
      final known = view(id: 'a', publishedAt: jan);
      final unknown = view(id: 'b', publishedAt: null);

      expect(
        compareEpisodes(const [SortSpec(SortField.publishedAt)], known, unknown),
        lessThan(0),
      );
      expect(
        compareEpisodes(
            const [SortSpec(SortField.publishedAt, descending: true)],
            known,
            unknown),
        lessThan(0),
        reason: 'unknown is not "the oldest"; flipping must not promote it',
      );
    });

    test('falls through to the next key on a tie', () {
      final a = view(id: 'a', playCount: 2, publishedAt: feb);
      final b = view(id: 'b', playCount: 2, publishedAt: jan);

      const specs = [
        SortSpec(SortField.playCount),
        SortSpec(SortField.publishedAt),
      ];
      expect(compareEpisodes(specs, a, b), greaterThan(0));
    });

    test('breaks total ties on id so the ordering is stable', () {
      final a = view(id: 'aaa');
      final b = view(id: 'bbb');

      expect(compareEpisodes(const [], a, b), lessThan(0));
      expect(compareEpisodes(const [], b, a), greaterThan(0));
      expect(compareEpisodes(const [], a, a), 0);
    });

    test('remainingTime accounts for how far in you are', () {
      final nearlyDone = view(
          id: 'a', duration: const Duration(minutes: 60),
          position: const Duration(minutes: 55));
      final barelyStarted = view(
          id: 'b', duration: const Duration(minutes: 30),
          position: const Duration(minutes: 1));

      expect(
        compareEpisodes(const [SortSpec(SortField.remainingTime)], nearlyDone,
            barelyStarted),
        lessThan(0),
      );
    });

    test('title sorting ignores case', () {
      final a = view(id: 'a', title: 'apple');
      final b = view(id: 'b', title: 'Banana');

      expect(compareEpisodes(const [SortSpec(SortField.title)], a, b),
          lessThan(0));
    });

    test('sorts a real list the way you would read it', () {
      final list = [
        view(id: 'old', publishedAt: jan),
        view(id: 'undated', publishedAt: null),
        view(id: 'new', publishedAt: feb),
      ];
      list.sort((a, b) => compareEpisodes(
          const [SortSpec(SortField.publishedAt, descending: true)], a, b));

      expect(list.map((v) => v.episode.id.value), ['new', 'old', 'undated']);
    });
  });
}
