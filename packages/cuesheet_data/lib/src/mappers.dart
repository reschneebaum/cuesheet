import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';
import 'normalize_url.dart';

/// Row-to-entity mapping.
///
/// This is the whole of the boundary: above it nothing knows about nullable
/// columns or foreign keys, below it nothing knows about the domain's
/// invariants. Keeping it in one small file makes the boundary auditable.
Podcast toPodcast(PodcastRow r) => Podcast(
      id: PodcastId(r.id),
      feedUrl: Uri.parse(r.feedUrl),
      title: r.title,
      author: r.author,
      artworkUrl: r.artworkUrl == null ? null : Uri.tryParse(r.artworkUrl!),
      description: r.description,
      lastFetchedAt: r.lastFetchedAt,
    );

Episode toEpisode(EpisodeRow r) => Episode(
      id: EpisodeId(r.id),
      podcastId: PodcastId(r.podcastId),
      title: r.title,
      enclosureUrl: Uri.parse(r.enclosureUrl),
      guid: r.guid,
      publishedAt: r.publishedAt,
      duration:
          r.durationMs == null ? null : Duration(milliseconds: r.durationMs!),
      description: r.description,
      artworkUrl: r.artworkUrl == null ? null : Uri.tryParse(r.artworkUrl!),
      feedPosition: r.feedPosition,
      isOrphaned: r.isOrphaned,
    );

/// A missing row means "not listened to", not "unknown" — so the absence maps
/// to a blank state rather than to null. Callers never have to ask which.
ListeningState toListeningState(ListeningRow? r, EpisodeId episodeId) =>
    r == null
        ? ListeningState(episodeId: episodeId)
        : ListeningState(
            episodeId: EpisodeId(r.episodeId),
            position: Duration(milliseconds: r.positionMs),
            playCount: r.playCount,
            startCount: r.startCount,
            firstPlayedAt: r.firstPlayedAt,
            lastPlayedAt: r.lastPlayedAt,
            finishedAt: r.finishedAt,
            explicitlyFinished: r.explicitlyFinished,
            countedThisSession: r.countedThisSession,
          );

PodcastsCompanion podcastCompanion(Podcast p) => PodcastsCompanion.insert(
      id: p.id.value,
      feedUrl: p.feedUrl.toString(),
      title: p.title,
      author: Value(p.author),
      artworkUrl: Value(p.artworkUrl?.toString()),
      description: Value(p.description),
      lastFetchedAt: Value(p.lastFetchedAt),
    );

EpisodesCompanion episodeCompanion(Episode e, {MatchRung? matchRung}) =>
    EpisodesCompanion.insert(
      id: e.id.value,
      podcastId: e.podcastId.value,
      enclosureUrl: e.enclosureUrl.toString(),
      normalizedEnclosureUrl: normalizeEnclosureUrl(e.enclosureUrl),
      title: e.title,
      guid: Value(e.guid),
      publishedAt: Value(e.publishedAt),
      durationMs: Value(e.duration?.inMilliseconds),
      description: Value(e.description),
      artworkUrl: Value(e.artworkUrl?.toString()),
      feedPosition: Value(e.feedPosition),
      matchRung: Value(matchRung),
      isOrphaned: Value(e.isOrphaned),
    );

ListeningStatesCompanion listeningCompanion(ListeningState s) =>
    ListeningStatesCompanion.insert(
      episodeId: s.episodeId.value,
      positionMs: Value(s.position.inMilliseconds),
      playCount: Value(s.playCount),
      startCount: Value(s.startCount),
      firstPlayedAt: Value(s.firstPlayedAt),
      lastPlayedAt: Value(s.lastPlayedAt),
      finishedAt: Value(s.finishedAt),
      explicitlyFinished: Value(s.explicitlyFinished),
      countedThisSession: Value(s.countedThisSession),
    );
