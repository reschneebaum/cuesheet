import 'package:meta/meta.dart';

import 'audio_engine.dart';
import 'ids.dart';
import 'listening.dart';
import 'listening_state.dart';
import 'queue_state.dart';

/// What the engine should be told to do after a tick.
@immutable
sealed class PlaybackCommand {
  const PlaybackCommand();
}

/// Nothing to do. The overwhelming majority of ticks.
final class KeepGoing extends PlaybackCommand {
  const KeepGoing();

  @override
  bool operator ==(Object other) => other is KeepGoing;

  @override
  int get hashCode => (KeepGoing).hashCode;

  @override
  String toString() => 'KeepGoing()';
}

/// Stop the engine. Playback has reached a natural end.
final class Halt extends PlaybackCommand {
  const Halt();

  @override
  bool operator ==(Object other) => other is Halt;

  @override
  int get hashCode => (Halt).hashCode;

  @override
  String toString() => 'Halt()';
}

/// Load [episode] and start playing it — the queue moved on.
final class PlayNext extends PlaybackCommand {
  const PlayNext(this.episode);

  final EpisodeId episode;

  @override
  bool operator ==(Object other) =>
      other is PlayNext && other.episode == episode;

  @override
  int get hashCode => Object.hash(PlayNext, episode);

  @override
  String toString() => 'PlayNext(${episode.value})';
}

/// Everything one tick implies.
@immutable
final class PlaybackOutcome {
  const PlaybackOutcome({
    required this.listening,
    required this.persist,
    this.queue,
    this.command = const KeepGoing(),
  });

  /// The listening state with this tick folded in. Always present, because
  /// every tick moves the playhead.
  final ListeningState listening;

  /// Whether [listening] must be written **now** rather than left to the
  /// debounce (§9).
  final bool persist;

  /// The queue after this tick, or null when the tick did not change it —
  /// which is every tick except a completion.
  final QueueState? queue;

  final PlaybackCommand command;

  @override
  String toString() =>
      'PlaybackOutcome(persist: $persist, queue: $queue, command: $command)';
}

/// How often the playhead is written while audio is rolling (§9).
const Duration positionWriteInterval = Duration(seconds: 5);

/// Fold one engine tick into listening state and the queue.
///
/// Pure, and the only place that decides what a tick means. The stateful half
/// — subscribing, timing the debounce, calling repositories — is the shell
/// around this and holds no rules of its own.
///
/// [lastWriteAt] is when the playhead was last persisted, or null if never.
/// Passing it in rather than holding it keeps this a function of its
/// arguments, which is what makes the durability rules testable without
/// waiting five seconds.
PlaybackOutcome onTick(
  PlaybackTick tick, {
  required QueueState queue,
  required ListeningState listening,
  required Duration? episodeDuration,
  required DateTime now,
  DateTime? lastWriteAt,
  ListeningThresholds thresholds = ListeningThresholds.standard,
}) {
  // The engine measured the file; the feed's `<itunes:duration>` was typed by
  // a person. Prefer the measurement when we have it.
  final duration = tick.duration ?? episodeDuration;

  if (tick.status == PlaybackStatus.completed) {
    return _onCompleted(tick, queue, listening, duration, now, thresholds);
  }

  final advanced = advance(
    listening,
    to: tick.position,
    episodeDuration: duration,
    now: now,
    thresholds: thresholds,
  );

  return PlaybackOutcome(
    listening: advanced,
    persist: _shouldWrite(tick.status, now, lastWriteAt),
  );
}

/// Anything that is not steady-state playback forces a write.
///
/// §9 lists pause, seek, episode change, queue mutation, interruption and
/// backgrounding as forcing events. The first is visible in the tick; the rest
/// are not, and are the shell's job to flush explicitly — a tick cannot tell a
/// seek from ordinary progress, and pretending otherwise would put a guess in
/// the one place that must not have one.
bool _shouldWrite(PlaybackStatus status, DateTime now, DateTime? lastWriteAt) {
  if (status != PlaybackStatus.playing) return true;
  if (lastWriteAt == null) return true;
  return now.difference(lastWriteAt) >= positionWriteInterval;
}

PlaybackOutcome _onCompleted(
  PlaybackTick tick,
  QueueState queue,
  ListeningState listening,
  Duration? duration,
  DateTime now,
  ListeningThresholds thresholds,
) {
  // Snap the playhead to the end. The engine says the audio ran out, which is
  // better evidence than the position it happened to report on the last tick.
  final finished = advance(
    listening,
    to: duration ?? tick.position,
    episodeDuration: duration,
    now: now,
    thresholds: thresholds,
  );

  PlaybackOutcome outcome(QueueState? next, PlaybackCommand command) =>
      PlaybackOutcome(
        listening: finished,
        persist: true,
        queue: next,
        command: command,
      );

  // Nothing should be playing at all, so whatever the engine is finishing is
  // not ours. Checked before staleness, because with no source `nowPlaying` is
  // null and every tick would otherwise read as merely stale.
  final source = queue.source;
  if (source == null) return outcome(null, const Halt());

  // A tick for something other than what the queue thinks is playing is
  // stale — a late report from an episode we already moved off. Its listening
  // state is still worth keeping; the queue is not its business.
  if (tick.episode != queue.nowPlaying) {
    return outcome(null, const KeepGoing());
  }

  switch (source) {
    // §5.3, and the decision that makes "play just this" safe: the detached
    // episode ends and playback stops. The queue is exactly where it was, and
    // resuming it is the user's call. Handing playback straight back to the
    // queue would mean a one-off tap eventually starts audio nobody asked for,
    // which is the class of surprise this app exists to refuse.
    case Detached():
      return outcome(_stopped(queue), const Halt());

    case FromQueue():
      final active = queue.active;
      final next = queue.position + 1;

      // End of the queue. The position stays put rather than running one past
      // the last item: `applyIntent` clamps to `items.length - 1` everywhere,
      // so an out-of-range position would be silently corrected by the next
      // intent and "finished the queue" would quietly become "sitting on the
      // last episode".
      if (active == null || next >= active.items.length) {
        return outcome(_stopped(queue), const Halt());
      }

      // Rule 1: the finished episode stays in the queue and the playhead moves
      // past it. Finishing is not an intent, so it does not get to mutate the
      // queue — the cuesheet is a document with a playhead, and everything
      // before that playhead is what you have listened to.
      return outcome(
        QueueState(
          active: active,
          position: next,
          source: const FromQueue(),
        ),
        PlayNext(active.items[next]),
      );
  }
}

/// The same queue with nothing playing.
///
/// Built rather than `copyWith`-ed on purpose: clearing a nullable field is
/// exactly the case `copyWith` cannot express, since it cannot tell "set this
/// to null" from "leave it alone". See `docs/notes/value-equality-and-copywith.md`.
QueueState _stopped(QueueState queue) =>
    QueueState(active: queue.active, position: queue.position);
