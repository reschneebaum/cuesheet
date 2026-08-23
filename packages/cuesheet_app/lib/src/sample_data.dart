import 'package:cuesheet_domain/cuesheet_domain.dart';

/// Fills an empty database with something to push buttons at.
///
/// Feed ingestion is Phase 3. Until then the debug harness needs its own way
/// to get data in, and hand-written fixtures are better than nothing: they put
/// at least one episode on each side of every boundary the filters can
/// express, which real feeds would only do by luck.
Future<void> insertSampleData({
  required PodcastRepository podcasts,
  required EpisodeRepository episodes,
  required ListeningRepository listening,
  required DateTime now,
}) async {

  const shows = [
    ('p1', 'The Rest Is History', 'Tom & Dominic'),
    ('p2', 'Search Engine', 'PJ Vogt'),
    ('p3', 'Twenty Thousand Hertz', 'Dallas Taylor'),
  ];

  for (final (id, title, author) in shows) {
    await podcasts.upsert(Podcast(
      id: PodcastId(id),
      feedUrl: Uri.parse('https://example.com/$id.xml'),
      title: title,
      author: author,
    ));
  }

  final built = <Episode>[];
  var n = 0;
  for (final (showId, _, _) in shows) {
    for (var i = 0; i < 6; i++) {
      n++;
      built.add(Episode(
        id: EpisodeId('e$n'),
        podcastId: PodcastId(showId),
        title: '$showId episode ${i + 1}',
        enclosureUrl: Uri.parse('https://cdn.example.com/e$n.mp3'),
        publishedAt: now.subtract(Duration(days: n * 3)),
        // A spread of lengths, including one with none at all, so the
        // duration filters and the unknown-duration rules both have subjects.
        duration: i == 5 ? null : Duration(minutes: 12 + i * 21),
        feedPosition: i,
      ));
    }
  }
  await episodes.upsertAll(built);

  // A spread of listening histories: untouched, barely tapped, part-way,
  // finished recently, finished long enough ago to be worth a relisten.
  await listening.save(ListeningState(
    episodeId: const EpisodeId('e2'),
    position: const Duration(seconds: 12),
    lastPlayedAt: now.subtract(const Duration(hours: 2)),
  ));
  await listening.save(ListeningState(
    episodeId: const EpisodeId('e3'),
    position: const Duration(minutes: 20),
    startCount: 1,
    firstPlayedAt: now.subtract(const Duration(days: 1)),
    lastPlayedAt: now.subtract(const Duration(days: 1)),
  ));
  await listening.save(ListeningState(
    episodeId: const EpisodeId('e4'),
    position: const Duration(minutes: 75),
    playCount: 1,
    startCount: 1,
    firstPlayedAt: now.subtract(const Duration(days: 4)),
    lastPlayedAt: now.subtract(const Duration(days: 4)),
    finishedAt: now.subtract(const Duration(days: 4)),
    countedThisSession: true,
  ));
  await listening.save(ListeningState(
    episodeId: const EpisodeId('e9'),
    position: const Duration(minutes: 96),
    playCount: 2,
    startCount: 2,
    firstPlayedAt: now.subtract(const Duration(days: 400)),
    lastPlayedAt: now.subtract(const Duration(days: 180)),
    finishedAt: now.subtract(const Duration(days: 180)),
    countedThisSession: true,
  ));
}
