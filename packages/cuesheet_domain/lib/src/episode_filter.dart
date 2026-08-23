import 'package:freezed_annotation/freezed_annotation.dart';

import 'episode_view.dart';
import 'ids.dart';
import 'listening.dart';
import 'listening_state.dart';

part 'episode_filter.freezed.dart';

/// A composable predicate over episodes.
///
/// The domain owns the *vocabulary*; `cuesheet_data` owns compiling it to SQL,
/// so nothing here knows that a database exists. [matchesFilter] below is a
/// reference implementation of the same semantics in plain Dart — it makes the
/// vocabulary testable without a database, and gives the SQL compiler an
/// oracle to be property-tested against.
///
/// Written as a freezed union so the variants get value equality and deep
/// collection comparison for free. Filters are values that get saved, loaded,
/// and compared; hand-writing `==` across eleven variants with `Set` and
/// `List` fields is exactly the boilerplate that goes quietly wrong.
@freezed
sealed class EpisodeFilter with _$EpisodeFilter {
  const factory EpisodeFilter.listenStateIs(Set<ListenState> states) =
      ListenStateIs;

  const factory EpisodeFilter.inPodcasts(Set<PodcastId> ids) = InPodcasts;

  const factory EpisodeFilter.inCategories(Set<CategoryId> ids) = InCategories;

  /// Inclusive on both ends; either bound may be omitted.
  const factory EpisodeFilter.durationBetween({Duration? min, Duration? max}) =
      DurationBetween;

  const factory EpisodeFilter.publishedBetween({DateTime? from, DateTime? to}) =
      PublishedBetween;

  const factory EpisodeFilter.lastPlayedBetween({DateTime? from, DateTime? to}) =
      LastPlayedBetween;

  const factory EpisodeFilter.playCountBetween({int? min, int? max}) =
      PlayCountBetween;

  /// Case-insensitive substring match on the episode title only. Searching
  /// podcast titles too is `AnyOf([TitleContains(t), PodcastTitleContains(t)])`
  /// once that exists — composing beats widening.
  const factory EpisodeFilter.titleContains(String text) = TitleContains;

  /// Vacuously true when empty.
  const factory EpisodeFilter.allOf(List<EpisodeFilter> children) = AllOf;

  /// Vacuously false when empty.
  const factory EpisodeFilter.anyOf(List<EpisodeFilter> children) = AnyOf;

  const factory EpisodeFilter.not(EpisodeFilter child) = Not;
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
