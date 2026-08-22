import 'package:meta/meta.dart';

import 'cuesheet.dart';
import 'ids.dart';

/// Where the currently-playing audio is coming from.
///
/// This is the mechanism that makes "just play this one episode" genuinely
/// safe rather than nominally safe: while [Detached], the active cuesheet and
/// its position are untouched, and finishing does not advance the queue.
@immutable
sealed class PlaybackSource {
  const PlaybackSource();
}

/// Playing the active cuesheet at [QueueState.position].
final class FromQueue extends PlaybackSource {
  const FromQueue();

  @override
  bool operator ==(Object other) => other is FromQueue;

  @override
  int get hashCode => (FromQueue).hashCode;

  @override
  String toString() => 'FromQueue()';
}

/// Playing one episode outside the queue entirely.
final class Detached extends PlaybackSource {
  const Detached(this.episode);

  final EpisodeId episode;

  @override
  bool operator ==(Object other) => other is Detached && other.episode == episode;

  @override
  int get hashCode => Object.hash(Detached, episode);

  @override
  String toString() => 'Detached(${episode.value})';
}

/// The whole of the app's queue state, as one immutable value.
///
/// Small on purpose: undo is a stack of these snapshots rather than a set of
/// command/inverse pairs, which cannot drift out of sync with reality.
@immutable
final class QueueState {
  const QueueState({this.active, this.position = 0, this.source});

  static const QueueState empty = QueueState();

  /// The cuesheet currently serving as the queue, if any.
  final Cuesheet? active;

  /// Index into [active]'s items. Meaningless when [active] is null or empty.
  final int position;

  /// What is playing, or null if nothing is.
  final PlaybackSource? source;

  /// The episode actually playing right now, accounting for detachment.
  ///
  /// There is exactly one source of truth for the queue position, so this is
  /// derived rather than stored — a stored copy is a bug waiting for a
  /// reorder to happen.
  EpisodeId? get nowPlaying {
    final sheet = active;
    return switch (source) {
      null => null,
      Detached(:final episode) => episode,
      FromQueue() =>
        (sheet != null && position >= 0 && position < sheet.items.length)
            ? sheet.items[position]
            : null,
    };
  }

  bool get isDetached => source is Detached;

  @override
  bool operator ==(Object other) =>
      other is QueueState &&
      other.active == active &&
      other.position == position &&
      other.source == source;

  @override
  int get hashCode => Object.hash(active, position, source);

  @override
  String toString() =>
      'QueueState(active: $active, position: $position, source: $source)';
}
