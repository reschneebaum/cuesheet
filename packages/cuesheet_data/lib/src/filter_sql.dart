import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:drift/drift.dart';

import 'database.dart';

/// Compiles the domain's filter and sort vocabulary into SQL.
///
/// The domain owns the vocabulary and ships `matchesFilter`, a reference
/// evaluation of the same semantics in plain Dart. This is the real
/// implementation; that one is the oracle it gets property-tested against.
/// Two implementations of one specification, and the tests keep them honest.
class FilterCompiler {
  FilterCompiler(this.db, {required this.now, this.thresholds = ListeningThresholds.standard});

  final CuesheetDatabase db;
  final DateTime now;
  final ListeningThresholds thresholds;

  /// Listening columns come from a LEFT JOIN, so they are null for an episode
  /// nobody has touched. The domain models that as a blank [ListeningState]
  /// rather than an absence, so every read coalesces to the same defaults.
  Expression<int> get _position =>
      coalesce([db.listeningStates.positionMs, const Constant(0)]);

  Expression<int> get _playCount =>
      coalesce([db.listeningStates.playCount, const Constant(0)]);

  Expression<bool> get _explicitlyFinished =>
      coalesce([db.listeningStates.explicitlyFinished, const Constant(false)]);

  /// Mirrors `_finishedByPosition` in the domain, including the short-episode
  /// case: an episode shorter than the finish threshold must be listened to in
  /// full rather than being born finished.
  ///
  /// Written as two disjoint AND-clauses instead of a CASE so it stays a plain
  /// boolean expression.
  Expression<bool> get _finishedByPosition {
    final duration = db.episodes.durationMs;
    final within = thresholds.finishWithin.inMilliseconds;
    final longEnough = duration.isBiggerThanValue(within) &
        _position.isBiggerOrEqual(duration - Variable(within));
    final tooShort =
        duration.isSmallerOrEqualValue(within) & _position.isBiggerOrEqual(duration);

    return duration.isNotNull() &
        _position.isBiggerThanValue(0) &
        (longEnough | tooShort);
  }

  Expression<bool> get _isFinished => _explicitlyFinished | _finishedByPosition;

  Expression<bool> get _isStale {
    final cutoff = now.subtract(thresholds.relistenAfter);
    return db.listeningStates.lastPlayedAt.isNotNull() &
        db.listeningStates.lastPlayedAt.isSmallerOrEqualValue(cutoff);
  }

  Expression<bool> _isState(ListenState state) => switch (state) {
        ListenState.unplayed => _isFinished.not() &
            _position.isSmallerOrEqualValue(thresholds.startAfter.inMilliseconds),
        ListenState.started => _isFinished.not() &
            _position.isBiggerThanValue(thresholds.startAfter.inMilliseconds),
        ListenState.finished => _isFinished & _isStale.not(),
        ListenState.relistenCandidate => _isFinished & _isStale,
      };

  Expression<bool> compile(EpisodeFilter filter) {
    switch (filter) {
      case ListenStateIs(:final states):
        if (states.isEmpty) return const Constant(false);
        return states.map(_isState).reduce((a, b) => a | b);

      case InPodcasts(:final ids):
        if (ids.isEmpty) return const Constant(false);
        return db.episodes.podcastId.isIn(ids.map((i) => i.value).toList());

      case InCategories(:final ids):
        if (ids.isEmpty) return const Constant(false);
        return existsQuery(
          db.selectOnly(db.episodeCategories)
            ..addColumns([db.episodeCategories.categoryId])
            ..where(
              db.episodeCategories.episodeId.equalsExp(db.episodes.id) &
                  db.episodeCategories.categoryId
                      .isIn(ids.map((i) => i.value).toList()),
            ),
        );

      case DurationBetween(:final min, :final max):
        var e = db.episodes.durationMs.isNotNull();
        if (min != null) {
          e = e & db.episodes.durationMs.isBiggerOrEqualValue(min.inMilliseconds);
        }
        if (max != null) {
          e = e & db.episodes.durationMs.isSmallerOrEqualValue(max.inMilliseconds);
        }
        return e;

      case PublishedBetween(:final from, :final to):
        return _dateBetween(db.episodes.publishedAt, from, to);

      case LastPlayedBetween(:final from, :final to):
        return _dateBetween(db.listeningStates.lastPlayedAt, from, to);

      case PlayCountBetween(:final min, :final max):
        var e = const Constant(true) as Expression<bool>;
        if (min != null) e = e & _playCount.isBiggerOrEqualValue(min);
        if (max != null) e = e & _playCount.isSmallerOrEqualValue(max);
        return e;

      case TitleContains(:final text):
        // instr() rather than LIKE: a search for "50%" or "foo_bar" must not
        // have its wildcards interpreted, and LIKE has no portable escape
        // without an ESCAPE clause drift will not emit.
        return FunctionCallExpression<int>('instr', [
          db.episodes.title.lower(),
          Variable<String>(text.toLowerCase()),
        ]).isBiggerThanValue(0);

      case AllOf(:final children):
        if (children.isEmpty) return const Constant(true);
        return children.map(compile).reduce((a, b) => a & b);

      case AnyOf(:final children):
        if (children.isEmpty) return const Constant(false);
        return children.map(compile).reduce((a, b) => a | b);

      case Not(:final child):
        return compile(child).not();
    }
  }

  Expression<bool> _dateBetween(
    GeneratedColumn<DateTime> column,
    DateTime? from,
    DateTime? to,
  ) {
    final typed = column as Expression<DateTime>;
    var e = column.isNotNull();
    if (from != null) e = e & typed.isBiggerOrEqualValue(from);
    if (to != null) e = e & typed.isSmallerOrEqualValue(to);
    return e;
  }

  /// The ordering for [specs].
  ///
  /// Each key emits *two* terms: an `IS NULL` term first, always ascending, so
  /// missing values sort last in both directions — matching `compareEpisodes`,
  /// where flipping to descending must not promote "unknown" to the top.
  /// Everything ends with episode id so the ordering is total and stable.
  List<OrderingTerm> ordering(List<SortSpec> specs) => [
        for (final spec in specs) ...[
          OrderingTerm.asc(_column(spec.field).isNull()),
          OrderingTerm(
            expression: _column(spec.field),
            mode: spec.descending ? OrderingMode.desc : OrderingMode.asc,
          ),
        ],
        OrderingTerm.asc(db.episodes.id),
      ];

  Expression<Object> _column(SortField field) => switch (field) {
        SortField.publishedAt => db.episodes.publishedAt,
        SortField.lastPlayedAt => db.listeningStates.lastPlayedAt,
        SortField.firstPlayedAt => db.listeningStates.firstPlayedAt,
        // Coalesced, like the filter path. An episode with no listening row
        // has a play count of zero in the domain, not an unknown one — sorting
        // it as NULL would push it to the bottom in both directions and
        // disagree with `compareEpisodes`. Caught by the agreement test.
        SortField.playCount => _playCount,
        SortField.duration => db.episodes.durationMs,
        SortField.remainingTime => FunctionCallExpression<int>('max', [
            db.episodes.durationMs - _position,
            const Constant(0),
          ]),
        SortField.title => db.episodes.title.lower(),
        SortField.podcastTitle => db.podcasts.title.lower(),
        SortField.feedPosition => db.episodes.feedPosition,
      };
}
