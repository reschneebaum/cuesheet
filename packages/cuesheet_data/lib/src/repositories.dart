import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:drift/drift.dart';

import 'database.dart';
import 'filter_sql.dart';
import 'mappers.dart';

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
