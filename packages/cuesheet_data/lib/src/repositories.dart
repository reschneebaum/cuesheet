import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:drift/drift.dart';

import 'database.dart';
import 'filter_json.dart';
import 'filter_sql.dart';
import 'mappers.dart';
import 'tables.dart';

class DriftPodcastRepository implements PodcastRepository {
  DriftPodcastRepository(this.db);

  final CuesheetDatabase db;

  @override
  Stream<List<Podcast>> watchAll() => (db.select(db.podcasts)
        ..orderBy([(t) => OrderingTerm.asc(t.title)]))
      .watch()
      .map((rows) => rows.map(toPodcast).toList());

  @override
  Future<Podcast?> byId(PodcastId id) async {
    final row = await (db.select(db.podcasts)
          ..where((t) => t.id.equals(id.value)))
        .getSingleOrNull();
    return row == null ? null : toPodcast(row);
  }

  @override
  Future<Podcast?> byFeedUrl(Uri feedUrl) async {
    final row = await (db.select(db.podcasts)
          ..where((t) => t.feedUrl.equals(feedUrl.toString())))
        .getSingleOrNull();
    return row == null ? null : toPodcast(row);
  }

  @override
  Future<void> upsert(Podcast podcast) =>
      db.into(db.podcasts).insertOnConflictUpdate(podcastCompanion(podcast));

  @override
  Future<void> remove(PodcastId id) =>
      (db.delete(db.podcasts)..where((t) => t.id.equals(id.value))).go();
}

class DriftListeningRepository implements ListeningRepository {
  DriftListeningRepository(this.db);

  final CuesheetDatabase db;

  @override
  Future<ListeningState> byEpisode(EpisodeId id) async {
    final row = await (db.select(db.listeningStates)
          ..where((t) => t.episodeId.equals(id.value)))
        .getSingleOrNull();
    return toListeningState(row, id);
  }

  @override
  Stream<ListeningState> watch(EpisodeId id) => (db.select(db.listeningStates)
        ..where((t) => t.episodeId.equals(id.value)))
      .watchSingleOrNull()
      .map((row) => toListeningState(row, id));

  @override
  Future<void> save(ListeningState state) => db
      .into(db.listeningStates)
      .insertOnConflictUpdate(listeningCompanion(state));
}

class DriftEpisodeRepository implements EpisodeRepository {
  DriftEpisodeRepository(this.db, {required this.clock});

  final CuesheetDatabase db;

  /// Injected because relisten candidacy depends on the current time, and a
  /// repository that reads the clock itself cannot be tested at a chosen
  /// instant.
  final DateTime Function() clock;

  @override
  Future<List<EpisodeView>> find(EpisodeQuery query) async =>
      _hydrate(await _select(query).get());

  @override
  Stream<List<EpisodeView>> watch(EpisodeQuery query) =>
      _select(query).watch().asyncMap(_hydrate);

  @override
  Future<EpisodeView?> byId(EpisodeId id) async {
    final statement = _join()..where(db.episodes.id.equals(id.value));
    final views = await _hydrate(await statement.get());
    return views.isEmpty ? null : views.first;
  }

  @override
  Future<void> upsertAll(Iterable<Episode> episodes) => db.batch((b) {
        for (final episode in episodes) {
          b.insert(db.episodes, episodeCompanion(episode),
              onConflict: DoUpdate((_) => episodeCompanion(episode)));
        }
      });

  JoinedSelectStatement<HasResultSet, dynamic> _join() =>
      db.select(db.episodes).join([
        innerJoin(db.podcasts, db.podcasts.id.equalsExp(db.episodes.podcastId)),
        leftOuterJoin(db.listeningStates,
            db.listeningStates.episodeId.equalsExp(db.episodes.id)),
      ]);

  JoinedSelectStatement<HasResultSet, dynamic> _select(EpisodeQuery query) {
    final compiler = FilterCompiler(db, now: clock());
    final statement = _join()
      ..where(compiler.compile(query.filter))
      ..orderBy(compiler.ordering(query.sort));
    if (query.limit != null) statement.limit(query.limit!);
    return statement;
  }

  /// Categories are fetched for the whole result set in one query rather than
  /// per row — the obvious per-row version is an N+1 that only hurts once the
  /// library is real.
  Future<List<EpisodeView>> _hydrate(List<TypedResult> rows) async {
    if (rows.isEmpty) return const [];

    final ids = [for (final r in rows) r.readTable(db.episodes).id];
    final byEpisode = <String, Set<CategoryId>>{};
    final links = await (db.select(db.episodeCategories)
          ..where((t) => t.episodeId.isIn(ids)))
        .get();
    for (final link in links) {
      (byEpisode[link.episodeId] ??= {}).add(CategoryId(link.categoryId));
    }

    return [
      for (final row in rows)
        EpisodeView(
          episode: toEpisode(row.readTable(db.episodes)),
          listening: toListeningState(
            row.readTableOrNull(db.listeningStates),
            EpisodeId(row.readTable(db.episodes).id),
          ),
          podcastTitle: row.readTable(db.podcasts).title,
          categories: byEpisode[row.readTable(db.episodes).id] ?? const {},
        ),
    ];
  }
}

class DriftCategoryRepository implements CategoryRepository {
  DriftCategoryRepository(this.db);

  final CuesheetDatabase db;

  @override
  Stream<List<Category>> watchAll() => (db.select(db.categories)
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch()
      .map((rows) => [
            for (final r in rows)
              Category(id: CategoryId(r.id), name: r.name, color: r.color),
          ]);

  @override
  Future<void> upsert(Category category) =>
      db.into(db.categories).insertOnConflictUpdate(CategoriesCompanion.insert(
            id: category.id.value,
            name: category.name,
            color: Value(category.color),
          ));

  @override
  Future<void> remove(CategoryId id) =>
      (db.delete(db.categories)..where((t) => t.id.equals(id.value))).go();

  @override
  Future<Set<CategoryId>> podcastCategories(PodcastId podcast) async {
    final rows = await (db.select(db.podcastCategories)
          ..where((t) => t.podcastId.equals(podcast.value)))
        .get();
    return {for (final r in rows) CategoryId(r.categoryId)};
  }

  @override
  Future<void> setPodcastCategories(PodcastId podcast, Set<CategoryId> ids) =>
      db.transaction(() async {
        await (db.delete(db.podcastCategories)
              ..where((t) => t.podcastId.equals(podcast.value)))
            .go();
        await db.batch((b) => b.insertAll(db.podcastCategories, [
              for (final id in ids)
                PodcastCategoriesCompanion.insert(
                    podcastId: podcast.value, categoryId: id.value),
            ]));
      });

  @override
  Future<void> setEpisodeCategories(EpisodeId episode, Set<CategoryId> ids) =>
      db.transaction(() async {
        await (db.delete(db.episodeCategories)
              ..where((t) => t.episodeId.equals(episode.value)))
            .go();
        await db.batch((b) => b.insertAll(db.episodeCategories, [
              for (final id in ids)
                EpisodeCategoriesCompanion.insert(
                    episodeId: episode.value, categoryId: id.value),
            ]));
      });
}

class DriftCuesheetRepository implements CuesheetRepository {
  DriftCuesheetRepository(this.db, {required this.clock, this.keepDisplaced = 10});

  final CuesheetDatabase db;
  final DateTime Function() clock;

  /// How many displaced queues to keep before pruning the oldest. Recovering
  /// a clobbered queue is a thing you do within minutes, not weeks.
  final int keepDisplaced;

  static const int _theOnlyQueue = 0;

  @override
  Stream<QueueState> watchQueue() => db
      .customSelect(
        'SELECT 1',
        // The queue changes when the pointer changes, when the active
        // cuesheet's metadata changes, and when its items are reordered. A
        // plain select on queue_states would miss the last of those.
        readsFrom: {db.queueStates, db.cuesheets, db.cuesheetItems},
      )
      .watch()
      .asyncMap((_) => queue());

  @override
  Future<QueueState> queue() async {
    final row = await (db.select(db.queueStates)
          ..where((t) => t.id.equals(_theOnlyQueue)))
        .getSingleOrNull();
    if (row == null) return QueueState.empty;

    final activeId = row.activeCuesheetId;
    final active = activeId == null ? null : await byId(CuesheetId(activeId));
    final detached = row.detachedEpisodeId;

    final source = switch (row.sourceKind) {
      null => null,
      PlaybackSourceKind.queue => const FromQueue(),
      PlaybackSourceKind.detached =>
        detached == null ? null : Detached(EpisodeId(detached)),
    };

    return QueueState(active: active, position: row.position, source: source);
  }

  @override
  Future<void> saveQueue(QueueState state, {Cuesheet? displaced}) =>
      db.transaction(() async {
        if (displaced != null) {
          await _write(displaced, displacedAt: clock());
        }
        final active = state.active;
        if (active != null) await _write(active);

        final source = state.source;
        await db.into(db.queueStates).insertOnConflictUpdate(
              QueueStatesCompanion.insert(
                id: const Value(_theOnlyQueue),
                activeCuesheetId: Value(active?.id.value),
                position: Value(state.position),
                sourceKind: Value(switch (source) {
                  null => null,
                  FromQueue() => PlaybackSourceKind.queue,
                  Detached() => PlaybackSourceKind.detached,
                }),
                detachedEpisodeId:
                    Value(source is Detached ? source.episode.value : null),
              ),
            );

        await _pruneDisplaced();
      });

  @override
  Stream<List<Cuesheet>> watchSaved() => (db.select(db.cuesheets)
        ..where((t) => t.kind.equalsValue(CuesheetKind.saved))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch()
      .asyncMap((rows) async =>
          [for (final row in rows) await _hydrate(row)]);

  @override
  Future<Cuesheet?> byId(CuesheetId id) async {
    final row = await (db.select(db.cuesheets)
          ..where((t) => t.id.equals(id.value)))
        .getSingleOrNull();
    return row == null ? null : _hydrate(row);
  }

  @override
  Future<void> save(Cuesheet cuesheet) => db.transaction(() => _write(cuesheet));

  @override
  Future<void> remove(CuesheetId id) =>
      (db.delete(db.cuesheets)..where((t) => t.id.equals(id.value))).go();

  @override
  Future<List<Cuesheet>> recentlyDisplaced({int limit = 5}) async {
    final rows = await (db.select(db.cuesheets)
          ..where((t) => t.displacedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.displacedAt)])
          ..limit(limit))
        .get();
    return [for (final row in rows) await _hydrate(row)];
  }

  Future<Cuesheet> _hydrate(CuesheetRow row) async {
    final items = await (db.select(db.cuesheetItems)
          ..where((t) => t.cuesheetId.equals(row.id))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    return Cuesheet(
      id: CuesheetId(row.id),
      kind: row.kind,
      title: row.title,
      items: [for (final i in items) EpisodeId(i.episodeId)],
      // `origin` is deliberately not restored. Only the intent's name is
      // stored, because knowing a queue came from "PlayFromHere" is useful and
      // replaying it is not. Provenance is lossy across persistence, and
      // Cuesheet's equality excludes origin so round-tripping stays clean.
    );
  }

  Future<void> _write(Cuesheet sheet, {DateTime? displacedAt}) async {
    await db.into(db.cuesheets).insert(
          CuesheetsCompanion.insert(
            id: sheet.id.value,
            kind: sheet.kind,
            createdAt: clock(),
            title: Value(sheet.title),
            originIntent: Value(sheet.origin?.runtimeType.toString()),
            displacedAt: Value(displacedAt),
          ),
          // createdAt is deliberately absent from the update: it records when
          // the cuesheet first existed, and re-saving it is not re-creating it.
          onConflict: DoUpdate((_) => CuesheetsCompanion(
                kind: Value(sheet.kind),
                title: Value(sheet.title),
                originIntent: Value(sheet.origin?.runtimeType.toString()),
                displacedAt: Value(displacedAt),
              )),
        );

    // Items are replaced wholesale. Diffing a reorder against the stored rows
    // would be more code for no benefit at these list sizes.
    await (db.delete(db.cuesheetItems)
          ..where((t) => t.cuesheetId.equals(sheet.id.value)))
        .go();
    await db.batch((b) => b.insertAll(db.cuesheetItems, [
          for (var i = 0; i < sheet.items.length; i++)
            CuesheetItemsCompanion.insert(
              cuesheetId: sheet.id.value,
              position: i,
              episodeId: sheet.items[i].value,
            ),
        ]));
  }

  Future<void> _pruneDisplaced() async {
    final keep = await (db.select(db.cuesheets)
          ..where((t) => t.displacedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.displacedAt)])
          ..limit(keepDisplaced))
        .get();
    await (db.delete(db.cuesheets)
          ..where((t) =>
              t.displacedAt.isNotNull() &
              t.kind.equalsValue(CuesheetKind.ephemeral) &
              t.id.isNotIn([for (final r in keep) r.id])))
        .go();
  }
}

class DriftSavedFilterRepository implements SavedFilterRepository {
  DriftSavedFilterRepository(this.db);

  final CuesheetDatabase db;

  @override
  Stream<List<SavedFilter>> watchAll() => (db.select(db.savedFilters)
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch()
      .map((rows) => [for (final row in rows) _toSavedFilter(row)]);

  @override
  Future<SavedFilter?> byId(SavedFilterId id) async {
    final row = await (db.select(db.savedFilters)
          ..where((t) => t.id.equals(id.value)))
        .getSingleOrNull();
    return row == null ? null : _toSavedFilter(row);
  }

  @override
  Future<void> upsert(SavedFilter filter) {
    final encoded = encodeQuery(filter.query);
    return db.into(db.savedFilters).insertOnConflictUpdate(
          SavedFiltersCompanion.insert(
            id: filter.id.value,
            name: filter.name,
            filterJson: encoded.filterJson,
            sortJson: encoded.sortJson,
          ),
        );
  }

  @override
  Future<void> remove(SavedFilterId id) =>
      (db.delete(db.savedFilters)..where((t) => t.id.equals(id.value))).go();

  SavedFilter _toSavedFilter(SavedFilterRow row) => SavedFilter(
        id: SavedFilterId(row.id),
        name: row.name,
        query: decodeQuery(
          filterJson: row.filterJson,
          sortJson: row.sortJson,
        ),
      );
}
