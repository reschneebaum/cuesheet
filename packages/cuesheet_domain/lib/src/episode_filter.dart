import 'package:meta/meta.dart';

import 'episode_view.dart';
import 'ids.dart';
import 'listening.dart';
import 'listening_state.dart';

/// A composable predicate over episodes.
///
/// The domain owns the *vocabulary*; `cuesheet_data` owns compiling it to SQL,
/// so nothing here knows that a database exists. [matchesFilter] below is a
/// reference implementation of the same semantics in plain Dart — it makes the
/// vocabulary testable now, and gives the SQL compiler an oracle to be checked
/// against later.
@immutable
sealed class EpisodeFilter {
  const EpisodeFilter();
}

final class ListenStateIs extends EpisodeFilter {
  const ListenStateIs(this.states);

  final Set<ListenState> states;
}

final class InPodcasts extends EpisodeFilter {
  const InPodcasts(this.ids);

  final Set<PodcastId> ids;
}

final class InCategories extends EpisodeFilter {
  const InCategories(this.ids);

  final Set<CategoryId> ids;
}

/// Inclusive on both ends; either bound may be omitted.
final class DurationBetween extends EpisodeFilter {
  const DurationBetween({this.min, this.max});

  final Duration? min;
  final Duration? max;
}

final class PublishedBetween extends EpisodeFilter {
  const PublishedBetween({this.from, this.to});

  final DateTime? from;
  final DateTime? to;
}

final class LastPlayedBetween extends EpisodeFilter {
  const LastPlayedBetween({this.from, this.to});

  final DateTime? from;
  final DateTime? to;
}

final class PlayCountBetween extends EpisodeFilter {
  const PlayCountBetween({this.min, this.max});

  final int? min;
  final int? max;
}

/// Case-insensitive substring match on the episode title only. Searching
/// podcast titles too is `AnyOf([TitleContains(t), PodcastTitleContains(t)])`
/// once that exists — composing beats widening.
final class TitleContains extends EpisodeFilter {
  const TitleContains(this.text);

  final String text;
}

/// Vacuously true when empty.
final class AllOf extends EpisodeFilter {
  const AllOf(this.children);

  final List<EpisodeFilter> children;
}

/// Vacuously false when empty.
final class AnyOf extends EpisodeFilter {
  const AnyOf(this.children);

  final List<EpisodeFilter> children;
}

final class Not extends EpisodeFilter {
  const Not(this.child);

  final EpisodeFilter child;
}

/// Reference evaluation of [filter] against [view].
bool matchesFilter(
  EpisodeFilter filter,
  EpisodeView view, {
  required DateTime now,
  ListeningThresholds thresholds = ListeningThresholds.standard,
}) {
  bool recurse(EpisodeFilter f) =>
      matchesFilter(f, view, now: now, thresholds: thresholds);

  switch (filter) {
    case ListenStateIs(:final states):
      final state = listenStateOf(
        view.listening,
        episodeDuration: view.episode.duration,
        now: now,
        thresholds: thresholds,
      );
      return states.contains(state);

    case InPodcasts(:final ids):
      return ids.contains(view.episode.podcastId);

    case InCategories(:final ids):
      return view.categories.any(ids.contains);

    case DurationBetween(:final min, :final max):
      final d = view.episode.duration;
      if (d == null) return false;
      return (min == null || d >= min) && (max == null || d <= max);

    case PublishedBetween(:final from, :final to):
      final at = view.episode.publishedAt;
      if (at == null) return false;
      return (from == null || !at.isBefore(from)) &&
          (to == null || !at.isAfter(to));

    case LastPlayedBetween(:final from, :final to):
      final at = view.listening.lastPlayedAt;
      if (at == null) return false;
      return (from == null || !at.isBefore(from)) &&
          (to == null || !at.isAfter(to));

    case PlayCountBetween(:final min, :final max):
      final n = view.listening.playCount;
      return (min == null || n >= min) && (max == null || n <= max);

    case TitleContains(:final text):
      return view.episode.title.toLowerCase().contains(text.toLowerCase());

    case AllOf(:final children):
      return children.every(recurse);

    case AnyOf(:final children):
      return children.any(recurse);

    case Not(:final child):
      return !recurse(child);
  }
}
