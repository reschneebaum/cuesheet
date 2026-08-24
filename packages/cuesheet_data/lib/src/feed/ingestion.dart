import 'dart:math';

import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../database.dart';
import '../normalize_url.dart';
import '../tables.dart';
import 'feed_transport.dart';
import 'match_episodes.dart';
import 'parse_feed.dart';

/// What one refresh did.
///
/// Exists to be shown. Half the value of ingestion is being able to answer
/// "what changed, and how did it match?" the moment it happens, rather than
/// inferring it from the library three weeks later.
@immutable
final class IngestionReport {
  const IngestionReport({
    required this.podcastId,
    this.notModified = false,
    this.added = 0,
    this.matched = 0,
    this.orphaned = 0,
    this.unorphaned = 0,
    this.deleted = 0,
    this.rungs = const {},
    this.warnings = const [],
  });

  const IngestionReport.unchanged(this.podcastId)
      : notModified = true,
        added = 0,
        matched = 0,
        orphaned = 0,
        unorphaned = 0,
        deleted = 0,
        rungs = const {},
        warnings = const [];

  final PodcastId podcastId;

  /// The server answered 304 and there was nothing to parse.
  final bool notModified;

  final int added;

  /// Items that found an existing row. The histogram in [rungs] says how.
  final int matched;

  /// Gone from the feed, kept because the user has done something to them.
  final int orphaned;

  /// Orphans the feed started listing again.
  final int unorphaned;

  /// Gone from the feed and untouched by the user, so genuinely gone.
  final int deleted;

  /// How this refresh's matches were made.
  ///
  /// A refresh that suddenly rescues forty episodes on `titleAndDate` means a
  /// feed rewrote its guids overnight — visible here, at the moment it
  /// happens, rather than only in the columns afterwards.
  final Map<MatchRung, int> rungs;

  final List<String> warnings;

  bool get changedAnything =>
      added + orphaned + unorphaned + deleted > 0 || matched > 0;

  @override
  String toString() => notModified
      ? 'IngestionReport(${podcastId.value}: not modified)'
      : 'IngestionReport(${podcastId.value}: +$added, ~$matched, '
          'orphaned $orphaned, unorphaned $unorphaned, deleted $deleted)';
}

/// Fetch, parse, match, write.
///
/// Talks to the database directly rather than through the repositories, and
/// deliberately: `etag` and `last-modified` are columns with no place on the
/// [Podcast] entity, and orphan policy needs to see across `listening_states`,
/// `cuesheet_items` and `episode_categories` in one transaction.
class FeedIngestion {
  FeedIngestion(
    this.db, {
    required this.transport,
    DateTime Function()? clock,
    String Function()? newEpisodeId,
    String Function()? newPodcastId,
  })  : clock = clock ?? DateTime.now,
        newEpisodeId = newEpisodeId ?? (() => newLocalId('ep')),
        newPodcastId = newPodcastId ?? (() => newLocalId('pod'));

  final CuesheetDatabase db;
  final FeedTransport transport;
  final DateTime Function() clock;
  final String Function() newEpisodeId;
  final String Function() newPodcastId;

  /// Subscribe, or refresh if this feed is already subscribed.
  ///
  /// Nothing is written until the feed has been fetched *and* parsed, so a URL
  /// that turns out not to be a feed leaves no broken subscription behind.
  Future<IngestionReport> subscribe(Uri feedUrl) async {
    final existing = await (db.select(db.podcasts)
          ..where((t) => t.feedUrl.equals(feedUrl.toString())))
        .getSingleOrNull();

    if (existing != null) return refresh(PodcastId(existing.id));

    return _ingest(podcastId: PodcastId(newPodcastId()), feedUrl: feedUrl);
  }

  Future<IngestionReport> refresh(PodcastId id) async {
    final row = await (db.select(db.podcasts)
          ..where((t) => t.id.equals(id.value)))
        .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(id.value, 'id', 'not a subscribed podcast');
    }

    return _ingest(
      podcastId: id,
      feedUrl: Uri.parse(row.feedUrl),
      currentTitle: row.title,
      etag: row.etag,
      lastModified: row.lastModified,
    );
  }

  Future<IngestionReport> _ingest({
    required PodcastId podcastId,
    required Uri feedUrl,
    String? currentTitle,
    String? etag,
    String? lastModified,
  }) async {
    final fetched = await transport.fetch(
      feedUrl,
      etag: etag,
      lastModified: lastModified,
    );

    final FeedBody received;
    switch (fetched) {
      case FeedUnchanged():
        await (db.update(db.podcasts)
              ..where((t) => t.id.equals(podcastId.value)))
            .write(PodcastsCompanion(lastFetchedAt: Value(clock())));
        return IngestionReport.unchanged(podcastId);
      case FeedBody():
        received = fetched;
    }

    // Throws if this is not a feed. Deliberately before any write.
    final parsed = parseFeed(received.body);

    final existingRows = await (db.select(db.episodes)
          ..where((t) => t.podcastId.equals(podcastId.value)))
        .get();
    final wasOrphaned = {
      for (final r in existingRows)
        if (r.isOrphaned) r.id,
    };

    final match = matchFeedItems(
      existing: [
        for (final r in existingRows)
          ExistingEpisode(
            id: EpisodeId(r.id),
            guid: r.guid,
            normalizedEnclosureUrl: r.normalizedEnclosureUrl,
            title: r.title,
            publishedAt: r.publishedAt,
          ),
      ],
      incoming: parsed.items,
      newId: newEpisodeId,
    );

    final keep = await _worthKeeping(match.vanished);
    final now = clock();

    final rungs = <MatchRung, int>{};
    var unorphaned = 0;
    for (final m in match.items) {
      rungs[m.rung] = (rungs[m.rung] ?? 0) + 1;
      if (wasOrphaned.contains(m.id.value)) unorphaned++;
    }

    final toOrphan = [
      for (final id in match.vanished)
        if (keep.contains(id.value)) id.value,
    ];
    final toDelete = [
      for (final id in match.vanished)
        if (!keep.contains(id.value)) id.value,
    ];

    await db.transaction(() async {
      await db.into(db.podcasts).insertOnConflictUpdate(
            PodcastsCompanion.insert(
              id: podcastId.value,
              feedUrl: feedUrl.toString(),
              // A feed that briefly forgets its own title must not overwrite a
              // good one with a hostname.
              title: parsed.title ?? currentTitle ?? feedUrl.host,
              author: Value(parsed.author),
              artworkUrl: Value(parsed.artworkUrl?.toString()),
              description: Value(parsed.description),
              lastFetchedAt: Value(now),
              etag: Value(received.etag),
              lastModified: Value(received.lastModified),
            ),
          );

      // One batch rather than a loop of awaits. A four-hundred-episode feed is
      // four hundred round trips otherwise, and drift propagates the enclosing
      // transaction through a zone — so the tempting Swift move of running the
      // writes concurrently in a task group is exactly the wrong shape here.
      await db.batch((b) {
        for (final m in match.items) {
          final companion = EpisodesCompanion.insert(
            id: m.id.value,
            podcastId: podcastId.value,
            enclosureUrl: m.item.enclosureUrl.toString(),
            normalizedEnclosureUrl: normalizeEnclosureUrl(m.item.enclosureUrl),
            title: m.item.title,
            guid: Value(m.item.guid),
            publishedAt: Value(m.item.publishedAt),
            durationMs: Value(m.item.duration?.inMilliseconds),
            description: Value(m.item.description),
            artworkUrl: Value(m.item.artworkUrl?.toString()),
            feedPosition: Value(m.item.feedPosition),
            // The latest rung, not the first: this column answers "how is this
            // row attached to that item right now?". The more interesting
            // event — a refresh where the rung changed — is answered by the
            // histogram on the report, at the moment it happens.
            matchRung: Value(m.rung),
            // Listed again, so no longer an orphan.
            isOrphaned: const Value(false),
          );
          b.insert(db.episodes, companion,
              onConflict: DoUpdate((_) => companion));
        }

        if (toOrphan.isNotEmpty) {
          b.update(
            db.episodes,
            const EpisodesCompanion(isOrphaned: Value(true)),
            where: (t) => t.id.isIn(toOrphan),
          );
        }
        if (toDelete.isNotEmpty) {
          b.deleteWhere(db.episodes, (t) => t.id.isIn(toDelete));
        }
      });
    });

    final newlyOrphaned =
        toOrphan.where((id) => !wasOrphaned.contains(id)).length;

    return IngestionReport(
      podcastId: podcastId,
      added: rungs[MatchRung.firstSighting] ?? 0,
      matched: match.items.length - (rungs[MatchRung.firstSighting] ?? 0),
      orphaned: newlyOrphaned,
      unorphaned: unorphaned,
      deleted: toDelete.length,
      rungs: Map.unmodifiable(rungs),
      warnings: parsed.warnings,
    );
  }

  /// Which of [vanished] must survive being dropped from the feed.
  ///
  /// §6 rule 5 says an episode with listening history is never deleted, and
  /// the same argument covers everything else the user authored: an episode
  /// sitting in a saved cuesheet, or one they filed under a category. Feeds
  /// trim to a rolling window as a matter of routine; that must not quietly
  /// cascade a saved queue's items away or unfile an episode. Anything the
  /// user has actually touched is orphaned rather than deleted; anything they
  /// never touched is genuinely gone.
  Future<Set<String>> _worthKeeping(List<EpisodeId> vanished) async {
    if (vanished.isEmpty) return const {};
    final ids = [for (final id in vanished) id.value];
    final keep = <String>{};

    final listening = await (db.select(db.listeningStates)
          ..where((t) => t.episodeId.isIn(ids)))
        .get();
    for (final row in listening) {
      final touched = row.positionMs > 0 ||
          row.playCount > 0 ||
          row.startCount > 0 ||
          row.explicitlyFinished ||
          row.lastPlayedAt != null;
      if (touched) keep.add(row.episodeId);
    }

    final queued = await (db.select(db.cuesheetItems)
          ..where((t) => t.episodeId.isIn(ids)))
        .get();
    keep.addAll(queued.map((r) => r.episodeId));

    final filed = await (db.select(db.episodeCategories)
          ..where((t) => t.episodeId.isIn(ids)))
        .get();
    keep.addAll(filed.map((r) => r.episodeId));

    return keep;
  }
}

final _random = Random();

/// A local surrogate id: milliseconds in base 36, then 40 bits of randomness.
///
/// Time-ordered so that a database dump reads in roughly the order things were
/// first seen, and random-suffixed because a four-hundred-episode feed is
/// ingested well inside one millisecond and a bare timestamp would collide
/// four hundred times. Never derived from feed content — that is the whole
/// point of §6.
String newLocalId(String prefix) {
  final time = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final noise = _random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0') +
      _random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
  return '$prefix-$time-$noise';
}
