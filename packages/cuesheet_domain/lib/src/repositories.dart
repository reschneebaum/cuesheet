import 'package:meta/meta.dart';

import 'episode.dart';
import 'episode_filter.dart';
import 'episode_view.dart';
import 'ids.dart';
import 'listening_state.dart';
import 'podcast.dart';
import 'sort_spec.dart';

/// What to select and in what order.
///
/// A saved smart list (§8) is a name plus one of these. It is a value, so it
/// serializes, and so a stored list needs no query code of its own.
@immutable
final class EpisodeQuery {
  const EpisodeQuery({
    this.filter = const AllOf([]),
    this.sort = const [SortSpec(SortField.publishedAt, descending: true)],
    this.limit,
  });

  /// Defaults to the vacuously-true filter: everything.
  final EpisodeFilter filter;
  final List<SortSpec> sort;
  final int? limit;
}

/// Declared here, implemented in `cuesheet_data`.
///
/// `abstract interface class` means these can be implemented but never
/// extended — the domain is specifying a contract, not offering a base class
/// to inherit behaviour from.
abstract interface class PodcastRepository {
  Stream<List<Podcast>> watchAll();

  Future<Podcast?> byId(PodcastId id);

  Future<Podcast?> byFeedUrl(Uri feedUrl);

  Future<void> upsert(Podcast podcast);

  Future<void> remove(PodcastId id);
}

abstract interface class EpisodeRepository {
  /// Re-emits whenever anything the query depends on changes.
  Stream<List<EpisodeView>> watch(EpisodeQuery query);

  Future<List<EpisodeView>> find(EpisodeQuery query);

  Future<EpisodeView?> byId(EpisodeId id);

  Future<void> upsertAll(Iterable<Episode> episodes);
}

abstract interface class ListeningRepository {
  /// Never null: an episode with no stored row has simply not been listened
  /// to, and a blank [ListeningState] says exactly that. Callers should not
  /// have to distinguish "no row" from "no progress".
  Future<ListeningState> byEpisode(EpisodeId id);

  Stream<ListeningState> watch(EpisodeId id);

  Future<void> save(ListeningState state);
}
