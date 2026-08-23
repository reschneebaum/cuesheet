import 'package:freezed_annotation/freezed_annotation.dart';

import 'ids.dart';

part 'episode.freezed.dart';

/// Feed metadata for one episode.
///
/// Carries no listening state whatsoever — that lives in [ListeningState],
/// keyed by [id], so that re-matching a mutated feed can rewrite everything
/// here without touching what the user has listened to. This split is the
/// single most important modelling decision in the project; the reasoning is
/// in `docs/ARCHITECTURE.md` §6.
@freezed
abstract class Episode with _$Episode {
  const factory Episode({
    required EpisodeId id,
    required PodcastId podcastId,
    required String title,
    required Uri enclosureUrl,

    /// The feed's own identifier, when it supplies a usable one. Never trusted
    /// as identity; used only as the first rung of the match ladder.
    String? guid,
    DateTime? publishedAt,
    Duration? duration,
    String? description,
    Uri? artworkUrl,

    /// Where the episode sat in the feed when last fetched. Feeds are not
    /// always in date order, and some are deliberately not.
    int? feedPosition,

    /// Set when an episode has fallen out of its feed's rolling window but has
    /// listening history worth keeping. Orphans are hidden, never deleted.
    @Default(false) bool isOrphaned,
  }) = _Episode;
}
