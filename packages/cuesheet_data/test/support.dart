import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:drift/native.dart';

/// A fresh database per test, held entirely in memory.
///
/// Real schema, real SQLite, real query planner — the only thing missing is
/// the disk. Fast enough to open one per test, which keeps tests independent.
CuesheetDatabase openTestDatabase() =>
    CuesheetDatabase(NativeDatabase.memory());

final DateTime now = DateTime.utc(2026, 6, 1, 12);

/// The corpus every agreement test runs against. Chosen to put at least one
/// episode on each side of every boundary the filter vocabulary can express.
Future<void> seed(CuesheetDatabase db) async {
  final podcasts = DriftPodcastRepository(db);
  final episodes = DriftEpisodeRepository(db, clock: () => now);
  final listening = DriftListeningRepository(db);

  await podcasts.upsert(Podcast(
    id: const PodcastId('p1'),
    feedUrl: Uri.parse('https://example.com/one.xml'),
    title: 'Show One',
  ));
  await podcasts.upsert(Podcast(
    id: const PodcastId('p2'),
    feedUrl: Uri.parse('https://example.com/two.xml'),
    title: 'Another Show',
  ));

  Episode ep(
    String id,
    String podcast,
    String title, {
    Duration? duration = const Duration(minutes: 60),
    DateTime? publishedAt,
    int? feedPosition,
  }) =>
      Episode(
        id: EpisodeId(id),
        podcastId: PodcastId(podcast),
        title: title,
        enclosureUrl: Uri.parse('https://cdn.example.com/$id.mp3'),
        duration: duration,
        publishedAt: publishedAt,
        feedPosition: feedPosition,
      );

  await episodes.upsertAll([
    ep('e1', 'p1', 'Alpha', publishedAt: DateTime.utc(2026, 1, 1), feedPosition: 1),
    ep('e2', 'p1', 'Beta', publishedAt: DateTime.utc(2026, 2, 1), feedPosition: 2),
    ep('e3', 'p1', 'Gamma', publishedAt: DateTime.utc(2026, 3, 1), feedPosition: 3),
    ep('e4', 'p2', 'Delta', publishedAt: DateTime.utc(2026, 4, 1)),
    ep('e5', 'p2', 'Epsilon 50% Off', duration: null),
    ep('e6', 'p2', 'Zeta', duration: const Duration(seconds: 20)),
    ep('e7', 'p1', 'Eta', publishedAt: DateTime.utc(2026, 5, 1)),
    ep('e8', 'p2', 'theta', duration: const Duration(minutes: 5), feedPosition: 9),
  ]);

  // e1 untouched: unplayed.
  // e2 ten minutes in: started.
  await listening.save(ListeningState(
    episodeId: const EpisodeId('e2'),
    position: const Duration(minutes: 10),
    startCount: 1,
    firstPlayedAt: now.subtract(const Duration(days: 2)),
    lastPlayedAt: now.subtract(const Duration(days: 2)),
  ));
  // e3 finished yesterday.
  await listening.save(ListeningState(
    episodeId: const EpisodeId('e3'),
    position: const Duration(minutes: 59, seconds: 50),
    playCount: 1,
    startCount: 1,
    firstPlayedAt: now.subtract(const Duration(days: 1)),
    lastPlayedAt: now.subtract(const Duration(days: 1)),
    finishedAt: now.subtract(const Duration(days: 1)),
    countedThisSession: true,
  ));
  // e4 finished long ago: a relisten candidate.
  await listening.save(ListeningState(
    episodeId: const EpisodeId('e4'),
    position: const Duration(minutes: 59, seconds: 50),
    playCount: 2,
    startCount: 2,
    firstPlayedAt: now.subtract(const Duration(days: 400)),
    lastPlayedAt: now.subtract(const Duration(days: 200)),
    finishedAt: now.subtract(const Duration(days: 200)),
    countedThisSession: true,
  ));
  // e5 five minutes into an episode of unknown length: started, never finishable.
  await listening.save(ListeningState(
    episodeId: const EpisodeId('e5'),
    position: const Duration(minutes: 5),
    startCount: 1,
    lastPlayedAt: now.subtract(const Duration(days: 5)),
  ));
  // e6 twenty seconds into a twenty-second episode: finished, despite being
  // well under the finish threshold.
  await listening.save(ListeningState(
    episodeId: const EpisodeId('e6'),
    position: const Duration(seconds: 20),
    playCount: 1,
    lastPlayedAt: now.subtract(const Duration(days: 3)),
    countedThisSession: true,
  ));
  // e7 marked finished by hand, from a standing start.
  await listening.save(const ListeningState(
    episodeId: EpisodeId('e7'),
    explicitlyFinished: true,
  ));
  // e8 untouched.

  await db.into(db.categories).insert(
      CategoriesCompanion.insert(id: 'news', name: 'News'));
  await db.into(db.categories).insert(
      CategoriesCompanion.insert(id: 'fiction', name: 'Fiction'));
  for (final (episode, category) in [
    ('e1', 'news'),
    ('e4', 'fiction'),
    ('e8', 'news'),
    ('e8', 'fiction'),
  ]) {
    await db.into(db.episodeCategories).insert(
        EpisodeCategoriesCompanion.insert(
            episodeId: episode, categoryId: category));
  }
}
