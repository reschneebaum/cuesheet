import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every dependency in the app is wired here and nowhere else.
///
/// The layers below have no idea Riverpod exists — repositories are plain
/// classes taking a database and a clock. This file is the single place where
/// the interfaces the domain declares get bound to the implementations
/// `cuesheet_data` provides, which is what makes the whole thing swappable in
/// tests with one `overrides:` entry.
final databaseProvider = Provider<CuesheetDatabase>((ref) {
  final db = CuesheetDatabase(driftDatabase(name: 'cuesheet'));
  ref.onDispose(db.close);
  return db;
});

/// Injected rather than called directly, so "now" is one overridable thing
/// instead of a hundred scattered `DateTime.now()` calls.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final podcastRepositoryProvider = Provider<PodcastRepository>(
    (ref) => DriftPodcastRepository(ref.watch(databaseProvider)));

final episodeRepositoryProvider = Provider<EpisodeRepository>(
    (ref) => DriftEpisodeRepository(ref.watch(databaseProvider),
        clock: ref.watch(clockProvider)));

final listeningRepositoryProvider = Provider<ListeningRepository>(
    (ref) => DriftListeningRepository(ref.watch(databaseProvider)));

final cuesheetRepositoryProvider = Provider<CuesheetRepository>(
    (ref) => DriftCuesheetRepository(ref.watch(databaseProvider),
        clock: ref.watch(clockProvider)));

final savedFilterRepositoryProvider = Provider<SavedFilterRepository>(
    (ref) => DriftSavedFilterRepository(ref.watch(databaseProvider)));

// ---------------------------------------------------------------------------
// Reactive state
// ---------------------------------------------------------------------------

/// Which query the episode list is showing. The only mutable UI state here.
class QuerySelection extends Notifier<EpisodeQuery> {
  @override
  EpisodeQuery build() => const EpisodeQuery();

  void select(EpisodeQuery query) => state = query;
}

final querySelectionProvider =
    NotifierProvider<QuerySelection, EpisodeQuery>(QuerySelection.new);

final episodesProvider = StreamProvider<List<EpisodeView>>((ref) => ref
    .watch(episodeRepositoryProvider)
    .watch(ref.watch(querySelectionProvider)));

/// Every episode by id, so the queue can show titles for the ids it holds.
final episodeIndexProvider =
    StreamProvider<Map<EpisodeId, EpisodeView>>((ref) => ref
        .watch(episodeRepositoryProvider)
        .watch(const EpisodeQuery(sort: []))
        .map((all) => {for (final v in all) v.episode.id: v}));

final queueProvider = StreamProvider<QueueState>(
    (ref) => ref.watch(cuesheetRepositoryProvider).watchQueue());

final savedCuesheetsProvider = StreamProvider<List<Cuesheet>>(
    (ref) => ref.watch(cuesheetRepositoryProvider).watchSaved());

final displacedProvider = FutureProvider<List<Cuesheet>>((ref) {
  // Depend on the queue so the recovery list refreshes whenever it changes.
  ref.watch(queueProvider);
  return ref.watch(cuesheetRepositoryProvider).recentlyDisplaced(limit: 5);
});

/// Snapshots of prior queue states. §5.4: undo is a stack of values, not a set
/// of inverse commands.
class UndoStack extends Notifier<List<QueueState>> {
  static const int _depth = 20;

  @override
  List<QueueState> build() => const [];

  void push(QueueState snapshot) =>
      state = [...state, snapshot].reversed.take(_depth).toList().reversed.toList();

  QueueState? pop() {
    if (state.isEmpty) return null;
    final last = state.last;
    state = state.sublist(0, state.length - 1);
    return last;
  }
}

final undoStackProvider =
    NotifierProvider<UndoStack, List<QueueState>>(UndoStack.new);
