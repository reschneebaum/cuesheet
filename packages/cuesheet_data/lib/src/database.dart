// Imported for the generated part file's benefit, not this file's: `part`
// splices database.g.dart into *this* library, so it resolves names against
// these imports. The generated code references CuesheetKind and MatchRung.
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:drift/drift.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Podcasts,
    Episodes,
    ListeningStates,
    Categories,
    PodcastCategories,
    EpisodeCategories,
    Cuesheets,
    CuesheetItems,
    SavedFilters,
    QueueStates,
  ],
)
class CuesheetDatabase extends _$CuesheetDatabase {
  CuesheetDatabase(super.e);

  @override
  int get schemaVersion => 1;

  /// Store timestamps as ISO-8601 text rather than unix seconds.
  ///
  /// The default truncates to whole seconds, which would make the database
  /// disagree with the domain about relisten staleness for sub-second
  /// differences — a discrepancy that only shows up under a property test and
  /// is miserable to find in the wild.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        beforeOpen: (details) async {
          // SQLite ignores foreign keys unless asked, per connection. Without
          // this the `references` declarations in tables.dart are decoration.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
