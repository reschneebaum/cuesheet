import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'category.dart';
import 'cuesheet.dart';
import 'episode.dart';
import 'episode_filter.dart';
import 'episode_view.dart';
import 'ids.dart';
import 'listening_state.dart';
import 'podcast.dart';
import 'saved_filter.dart';
import 'queue_state.dart';
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

  static const _sortEquality = ListEquality<SortSpec>();

  @override
  bool operator ==(Object other) =>
      other is EpisodeQuery &&
      other.filter == filter &&
      other.limit == limit &&
      _sortEquality.equals(other.sort, sort);

  @override
  int get hashCode => Object.hash(filter, limit, _sortEquality.hash(sort));

  @override
  String toString() => 'EpisodeQuery($filter, sort: $sort, limit: $limit)';
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

abstract interface class CuesheetRepository {
  /// The live queue. Emits on every change, including position.
  Stream<QueueState> watchQueue();

  Future<QueueState> queue();

  /// Persist the queue.
  ///
  /// [displaced] is the ephemeral cuesheet this change threw away, as reported
  /// by `applyIntent`. It is stamped and kept rather than deleted — recovering
  /// an accidentally-clobbered queue is one of the specific things this app
  /// exists to do (§5.4). Older displaced cuesheets are pruned.
  Future<void> saveQueue(QueueState state, {Cuesheet? displaced});

  Stream<List<Cuesheet>> watchSaved();

  Future<Cuesheet?> byId(CuesheetId id);

  /// Insert or update. Promotion from ephemeral to saved is just a save with a
  /// changed kind and a title, which is the point of them being one entity.
  Future<void> save(Cuesheet cuesheet);

  Future<void> remove(CuesheetId id);

  /// Ephemeral cuesheets that were replaced, newest first.
  Future<List<Cuesheet>> recentlyDisplaced({int limit});
}

abstract interface class CategoryRepository {
  Stream<List<Category>> watchAll();

  Future<void> upsert(Category category);

  Future<void> remove(CategoryId id);

  /// Replaces the whole set for that podcast, rather than adding to it.
  Future<void> setPodcastCategories(PodcastId podcast, Set<CategoryId> ids);

  Future<Set<CategoryId>> podcastCategories(PodcastId podcast);

  Future<void> setEpisodeCategories(EpisodeId episode, Set<CategoryId> ids);
}

abstract interface class SavedFilterRepository {
  Stream<List<SavedFilter>> watchAll();

  Future<SavedFilter?> byId(SavedFilterId id);

  Future<void> upsert(SavedFilter filter);

  Future<void> remove(SavedFilterId id);
}
