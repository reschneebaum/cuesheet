import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:drift/drift.dart';

// Every table names its generated row class explicitly, with a `Row` suffix.
//
// Without this, drift's default singularisation produces `Episode`,
// `Podcast`, `ListeningState`, and `Cuesheet` — colliding head-on with the
// domain entities of the same names. The collision is a useful accident: a
// row is not an entity. It is a record of what SQLite holds, with nullable
// columns where the domain has defaults and foreign keys where the domain has
// composition. Keeping the names apart keeps the mapping honest and makes it
// obvious, at every use site, which side of the boundary you are on.

/// Which rung of the identity ladder (§6) matched an incoming feed item to an
/// existing row. Stored so that "how did this match?" is answerable from the
/// database rather than reconstructed from guesswork months later.
enum MatchRung { guid, enclosureUrl, titleAndDate, firstSighting }

@TableIndex(name: 'idx_episodes_feed', columns: {#podcastId, #publishedAt})
@TableIndex(name: 'idx_episodes_guid', columns: {#guid})
@TableIndex(name: 'idx_episodes_enclosure', columns: {#normalizedEnclosureUrl})
@DataClassName('EpisodeRow')
class Episodes extends Table {
  /// A local surrogate key, generated once at first sight and never derived
  /// from feed content. See `docs/ARCHITECTURE.md` §6.
  TextColumn get id => text()();

  TextColumn get podcastId =>
      text().references(Podcasts, #id, onDelete: KeyAction.cascade)();

  TextColumn get guid => text().nullable()();
  TextColumn get enclosureUrl => text()();
  TextColumn get normalizedEnclosureUrl => text()();
  TextColumn get title => text()();
  DateTimeColumn get publishedAt => dateTime().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get artworkUrl => text().nullable()();
  IntColumn get feedPosition => integer().nullable()();
  TextColumn get matchRung => textEnum<MatchRung>().nullable()();

  /// Gone from the feed, but kept because it has listening history.
  BoolColumn get isOrphaned => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PodcastRow')
class Podcasts extends Table {
  TextColumn get id => text()();
  TextColumn get feedUrl => text().unique()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get artworkUrl => text().nullable()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get lastFetchedAt => dateTime().nullable()();

  /// Conditional-request headers, so a refresh that changed nothing costs
  /// nothing.
  TextColumn get etag => text().nullable()();
  TextColumn get lastModified => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Deliberately its own table, keyed by the local episode id, so that
/// re-matching a mutated feed can rewrite every column in [Episodes] without
/// touching a single thing the user actually did.
@TableIndex(name: 'idx_listening_last_played', columns: {#lastPlayedAt})
@DataClassName('ListeningRow')
class ListeningStates extends Table {
  TextColumn get episodeId =>
      text().references(Episodes, #id, onDelete: KeyAction.cascade)();

  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get startCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get firstPlayedAt => dateTime().nullable()();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  BoolColumn get explicitlyFinished =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get countedThisSession =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {episodeId};
}

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get color => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PodcastCategoryRow')
class PodcastCategories extends Table {
  TextColumn get podcastId =>
      text().references(Podcasts, #id, onDelete: KeyAction.cascade)();
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {podcastId, categoryId};
}

@DataClassName('EpisodeCategoryRow')
class EpisodeCategories extends Table {
  TextColumn get episodeId =>
      text().references(Episodes, #id, onDelete: KeyAction.cascade)();
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {episodeId, categoryId};
}

/// Ephemeral and saved playlists in one table, distinguished by [kind] — the
/// same single-entity decision the domain makes (§7).
@DataClassName('CuesheetRow')
class Cuesheets extends Table {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<CuesheetKind>()();
  TextColumn get title => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  /// The name of the intent that produced this cuesheet, for provenance.
  /// Deliberately just a tag rather than a serialized intent — knowing it came
  /// from "PlayFromHere" is useful; replaying it is not.
  TextColumn get originIntent => text().nullable()();

  /// Exactly one cuesheet is the queue. Enforced in code, not by the schema.
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();

  /// Set when this ephemeral cuesheet was displaced by another. Retained
  /// rather than deleted so a clobbered queue can be recovered (§5.4).
  DateTimeColumn get displacedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'idx_cuesheet_items_order', columns: {#cuesheetId, #position})
@DataClassName('CuesheetItemRow')
class CuesheetItems extends Table {
  TextColumn get cuesheetId =>
      text().references(Cuesheets, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get episodeId =>
      text().references(Episodes, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {cuesheetId, position};
}

/// A saved smart list: a name plus a serialized [EpisodeQuery]. Sort-driven
/// only — see §8 for why there is no manual-order column here.
@DataClassName('SavedFilterRow')
class SavedFilters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get filterJson => text()();
  TextColumn get sortJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
