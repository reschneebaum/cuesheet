import 'package:meta/meta.dart';

import 'ids.dart';

/// Which direction `PlayFromHere` runs through the list it was invoked on.
enum TraversalOrder { ascending, descending }

/// The only sanctioned way to change the queue.
///
/// Sealed, so `switch` over it is checked for exhaustiveness at compile time:
/// adding a new intent breaks every site that must learn to handle it, which
/// is the whole reason the algebra is modelled as a closed set of values
/// rather than as methods on a queue object.
@immutable
sealed class PlaybackIntent {
  const PlaybackIntent();
}

/// Play one episode without touching the queue at all.
///
/// Sets the playback source to detached; see [ARCHITECTURE.md] §5.3.
final class PlayJustThis extends PlaybackIntent {
  const PlayJustThis(this.episode);

  final EpisodeId episode;
}

/// Build a new ephemeral cuesheet out of the list currently on screen,
/// starting at [episode] and running in [order].
final class PlayFromHere extends PlaybackIntent {
  const PlayFromHere(this.episode, this.order);

  final EpisodeId episode;
  final TraversalOrder order;
}

/// Place [episode] immediately after whatever is playing.
final class InsertNext extends PlaybackIntent {
  const InsertNext(this.episode);

  final EpisodeId episode;
}

/// Put [episode] at the end of the queue. Never starts playback.
final class AppendToQueue extends PlaybackIntent {
  const AppendToQueue(this.episode);

  final EpisodeId episode;
}

/// Discard the current queue in favour of [episodes], starting at [startAt].
final class ReplaceQueue extends PlaybackIntent {
  const ReplaceQueue(this.episodes, {this.startAt = 0});

  final List<EpisodeId> episodes;
  final int startAt;
}

final class RemoveFromQueue extends PlaybackIntent {
  const RemoveFromQueue(this.episode);

  final EpisodeId episode;
}

final class ReorderQueue extends PlaybackIntent {
  const ReorderQueue({required this.from, required this.to});

  final int from;
  final int to;
}
