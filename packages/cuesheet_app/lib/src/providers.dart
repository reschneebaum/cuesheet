import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_playback/cuesheet_playback.dart';
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
// Ingestion and search
// ---------------------------------------------------------------------------

/// Overridden in tests with `FakeFeedTransport`, which is the only reason no
/// widget test in this package touches the network.
final feedTransportProvider =
    Provider<FeedTransport>((ref) => HttpFeedTransport());

final podcastDirectoryProvider =
    Provider<PodcastDirectory>((ref) => ITunesPodcastDirectory());

/// Overridden with `FakeAudioEngine` in every widget test. Plugins do not work
/// under `flutter test` at all — there is no engine and no channel to answer —
/// so this override is not a convenience, it is the only way the app is
/// testable. See `docs/notes/plugins-and-platform-channels.md`.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = JustAudioEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

final feedIngestionProvider = Provider<FeedIngestion>((ref) => FeedIngestion(
      ref.watch(databaseProvider),
      transport: ref.watch(feedTransportProvider),
      clock: ref.watch(clockProvider),
    ));

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

/// Which podcast the list is narrowed to, or null for all of them.
///
/// Kept apart from [querySelectionProvider] rather than folded into its filter
/// so the two compose: picking a podcast must not clear the listen-state chip,
/// and the chips can keep deciding what is selected by plain `==` on a value.
class PodcastFilter extends Notifier<PodcastId?> {
  @override
  PodcastId? build() => null;

  void select(PodcastId? id) => state = id;
}

final podcastFilterProvider =
    NotifierProvider<PodcastFilter, PodcastId?>(PodcastFilter.new);

final episodesProvider = StreamProvider<List<EpisodeView>>((ref) {
  final selected = ref.watch(querySelectionProvider);
  final podcast = ref.watch(podcastFilterProvider);

  return ref.watch(episodeRepositoryProvider).watch(EpisodeQuery(
        filter: podcast == null
            ? selected.filter
            : AllOf([selected.filter, InPodcasts({podcast})]),
        sort: selected.sort,
        limit: selected.limit,
      ));
});

/// Diagnostic only: which rung of §6's identity ladder attached each episode
/// to its feed item.
///
/// Read straight off the row rather than through [EpisodeView], deliberately.
/// The rung is ingestion bookkeeping — it answers "how did this match?" when
/// something looks wrong — and putting it on a domain entity would mean the
/// domain knowing that feeds exist. The debug harness is allowed to reach past
/// the repositories for it; nothing else is.
final matchRungsProvider = StreamProvider<Map<EpisodeId, MatchRung>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.episodes).watch().map((rows) => {
        // Null-aware map value: an episode with no recorded rung is absent
        // from the map rather than present with a null.
        for (final row in rows) EpisodeId(row.id): ?row.matchRung,
      });
});

/// Every episode by id, so the queue can show titles for the ids it holds.
final episodeIndexProvider =
    StreamProvider<Map<EpisodeId, EpisodeView>>((ref) => ref
        .watch(episodeRepositoryProvider)
        .watch(const EpisodeQuery(sort: []))
        .map((all) => {for (final v in all) v.episode.id: v}));

final podcastsProvider = StreamProvider<List<Podcast>>(
    (ref) => ref.watch(podcastRepositoryProvider).watchAll());

/// The query the directory has actually been asked for, as opposed to what is
/// currently in the text field. Searching on every keystroke would be one
/// network round trip per character.
class DirectoryQuery extends Notifier<String> {
  @override
  String build() => '';

  void submit(String query) => state = query.trim();
}

final directoryQueryProvider =
    NotifierProvider<DirectoryQuery, String>(DirectoryQuery.new);

final directoryResultsProvider =
    FutureProvider<List<DirectoryResult>>((ref) async {
  final query = ref.watch(directoryQueryProvider);
  if (query.isEmpty) return const [];
  return ref.watch(podcastDirectoryProvider).search(query);
});

/// What the last few refreshes did, newest first.
///
/// The whole point of the harness: an ingestion that quietly orphans six
/// episodes should say so somewhere a human can read it.
class IngestionLog extends Notifier<List<String>> {
  static const int _depth = 30;

  @override
  List<String> build() => const [];

  void add(String line) => state = [line, ...state].take(_depth).toList();

  void clear() => state = const [];
}

final ingestionLogProvider =
    NotifierProvider<IngestionLog, List<String>>(IngestionLog.new);

/// One podcast's episodes, in the order that screen is showing them.
///
/// Keyed by a record so the sort is part of the identity: flipping to
/// oldest-first is a different query, not the same query mutated, and Riverpod
/// keeps both alive while the screen is on either.
final podcastEpisodesProvider = StreamProvider.family<List<EpisodeView>,
    ({PodcastId podcast, bool newestFirst})>(
  (ref, key) => ref.watch(episodeRepositoryProvider).watch(EpisodeQuery(
        filter: InPodcasts({key.podcast}),
        sort: [SortSpec(SortField.publishedAt, descending: key.newestFirst)],
      )),
);

/// The engine's own reports, for the transport bar.
///
/// A second listener on the same broadcast stream the controller uses — which
/// is why `AudioEngine.ticks` is broadcast rather than single-subscription.
final playbackTickProvider = StreamProvider<PlaybackTick>(
    (ref) => ref.watch(audioEngineProvider).ticks);

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
