import 'listening_state.dart';

/// How an episode reads in a list, and what the filter vocabulary selects on.
enum ListenState { unplayed, started, finished, relistenCandidate }

/// The position at or beyond which an episode counts as finished.
///
/// Normally [ListeningThresholds.finishWithin] short of the end. For an
/// episode shorter than that threshold the subtraction would put the boundary
/// at or before zero, which would make every short episode born finished, so
/// those require the whole thing.
Duration _finishBoundary(Duration duration, ListeningThresholds thresholds) {
  final boundary = duration - thresholds.finishWithin;
  return boundary <= Duration.zero ? duration : boundary;
}

bool _finishedByPosition(
  Duration position,
  Duration? duration,
  ListeningThresholds thresholds,
) =>
    duration != null &&
    position > Duration.zero &&
    position >= _finishBoundary(duration, thresholds);

/// Whether [state] counts as finished — by position, or because the user said
/// so. An episode whose duration the feed never supplied can only be finished
/// explicitly.
bool isFinished(
  ListeningState state, {
  required Duration? episodeDuration,
  ListeningThresholds thresholds = ListeningThresholds.standard,
}) =>
    state.explicitlyFinished ||
    _finishedByPosition(state.position, episodeDuration, thresholds);

/// Where [state] sits in the unplayed / started / finished / relisten cycle.
///
/// [now] is a parameter rather than a call to `DateTime.now()` so this stays a
/// pure function: relisten candidacy depends on the clock, and a domain that
/// reads the clock itself cannot be tested without waiting.
ListenState listenStateOf(
  ListeningState state, {
  required Duration? episodeDuration,
  required DateTime now,
  ListeningThresholds thresholds = ListeningThresholds.standard,
}) {
  if (isFinished(state, episodeDuration: episodeDuration, thresholds: thresholds)) {
    final last = state.lastPlayedAt;
    final stale =
        last != null && now.difference(last) >= thresholds.relistenAfter;
    return stale ? ListenState.relistenCandidate : ListenState.finished;
  }
  // Strictly greater: the threshold must be *exceeded*. This is the guard that
  // stops a stray tap moving an episode out of unplayed.
  if (state.position > thresholds.startAfter) return ListenState.started;
  return ListenState.unplayed;
}

/// Time left, or null when the feed never told us how long the episode is.
Duration? remaining(ListeningState state, {required Duration? episodeDuration}) {
  if (episodeDuration == null) return null;
  final left = episodeDuration - state.position;
  return left.isNegative ? Duration.zero : left;
}

/// Move the playhead to [to] and fold in everything that implies.
///
/// This is the only function that increments [ListeningState.playCount] or
/// [ListeningState.startCount], so the rules about what counts as a listen
/// live in exactly one place.
ListeningState advance(
  ListeningState state, {
  required Duration to,
  required Duration? episodeDuration,
  required DateTime now,
  ListeningThresholds thresholds = ListeningThresholds.standard,
}) {
  // A session ends when the playhead drops back to the start threshold or
  // below. Scrubbing backwards *within* a session does not end it, which is
  // why one listen cannot be counted twice by rewinding a minute.
  final sessionEnded = to <= thresholds.startAfter;

  var counted = sessionEnded ? false : state.countedThisSession;
  var explicitlyFinished = sessionEnded ? false : state.explicitlyFinished;

  var startCount = state.startCount;
  var firstPlayedAt = state.firstPlayedAt;
  final wasStarted = state.position > thresholds.startAfter;
  final isStarted = to > thresholds.startAfter;
  if (!wasStarted && isStarted) {
    startCount += 1;
    firstPlayedAt ??= now;
  }

  var playCount = state.playCount;
  var finishedAt = state.finishedAt;
  if (_finishedByPosition(to, episodeDuration, thresholds) && !counted) {
    playCount += 1;
    counted = true;
    finishedAt = now;
  }

  return state.copyWith(
    position: to,
    startCount: startCount,
    playCount: playCount,
    firstPlayedAt: firstPlayedAt,
    lastPlayedAt: now,
    finishedAt: finishedAt,
    explicitlyFinished: explicitlyFinished,
    countedThisSession: counted,
  );
}

/// Mark [state] finished by hand.
///
/// Jumps the playhead to the end when the duration is known, so the episode
/// stops reporting time remaining. Counts a play unless this session already
/// counted one — marking finished after listening to the end is not two
/// listens.
ListeningState markFinished(
  ListeningState state, {
  required DateTime now,
  required Duration? episodeDuration,
}) =>
    state.copyWith(
      position: episodeDuration ?? state.position,
      explicitlyFinished: true,
      playCount: state.countedThisSession ? state.playCount : state.playCount + 1,
      countedThisSession: true,
      finishedAt: now,
      lastPlayedAt: now,
    );

/// Send [state] back to the top without erasing what already happened.
///
/// Play and start counts survive: you did listen to it, and the calibration
/// data that feeds sorting and relisten candidacy should not be rewritable by
/// a UI gesture that only means "show this as new again".
ListeningState markUnplayed(ListeningState state) => state.copyWith(
      position: Duration.zero,
      explicitlyFinished: false,
      countedThisSession: false,
      finishedAt: null,
    );
