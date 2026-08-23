import 'package:meta/meta.dart';

import 'episode_view.dart';
import 'listening.dart';

enum SortField {
  publishedAt,
  lastPlayedAt,
  firstPlayedAt,
  playCount,
  duration,
  remainingTime,
  title,
  podcastTitle,
  feedPosition,
}

/// One key in an ordering. Sorting takes a *list* of these — "last listened
/// descending, then published descending" is the kind of thing people reach
/// for manual ordering to express, and multi-key sorting absorbs most of that
/// demand (§8).
@immutable
final class SortSpec {
  const SortSpec(this.field, {this.descending = false});

  final SortField field;
  final bool descending;

  @override
  bool operator ==(Object other) =>
      other is SortSpec && other.field == field && other.descending == descending;

  @override
  int get hashCode => Object.hash(field, descending);

  @override
  String toString() => 'SortSpec(${field.name}${descending ? ' desc' : ''})';
}

/// Compare two episodes under [specs].
///
/// Missing values always sort last, in both directions: an episode with no
/// publication date is not "the oldest", it is unknown, and flipping the
/// direction should not promote it to the top. Ties break on episode id so the
/// ordering is total and stable.
int compareEpisodes(List<SortSpec> specs, EpisodeView a, EpisodeView b) {
  for (final spec in specs) {
    final result = _compareOne(spec, a, b);
    if (result != 0) return result;
  }
  return a.episode.id.value.compareTo(b.episode.id.value);
}

int _compareOne(SortSpec spec, EpisodeView a, EpisodeView b) {
  final ordering = switch (spec.field) {
    SortField.publishedAt =>
      _nullsLast(a.episode.publishedAt, b.episode.publishedAt),
    SortField.lastPlayedAt =>
      _nullsLast(a.listening.lastPlayedAt, b.listening.lastPlayedAt),
    SortField.firstPlayedAt =>
      _nullsLast(a.listening.firstPlayedAt, b.listening.firstPlayedAt),
    SortField.playCount =>
      _nullsLast(a.listening.playCount, b.listening.playCount),
    SortField.duration => _nullsLast(a.episode.duration, b.episode.duration),
    SortField.remainingTime => _nullsLast(
        remaining(a.listening, episodeDuration: a.episode.duration),
        remaining(b.listening, episodeDuration: b.episode.duration),
      ),
    SortField.title => _nullsLast(
        a.episode.title.toLowerCase(),
        b.episode.title.toLowerCase(),
      ),
    SortField.podcastTitle =>
      _nullsLast(a.podcastTitle.toLowerCase(), b.podcastTitle.toLowerCase()),
    SortField.feedPosition =>
      _nullsLast(a.episode.feedPosition, b.episode.feedPosition),
  };

  // A null-ordering decision must survive the direction flip, so it is applied
  // after the reversal rather than before it.
  if (ordering.isNullOrdering) return ordering.value;
  return spec.descending ? -ordering.value : ordering.value;
}

typedef _Ordering = ({int value, bool isNullOrdering});

_Ordering _nullsLast<T extends Comparable<Object>>(T? a, T? b) {
  if (a == null && b == null) return (value: 0, isNullOrdering: false);
  if (a == null) return (value: 1, isNullOrdering: true);
  if (b == null) return (value: -1, isNullOrdering: true);
  return (value: a.compareTo(b), isNullOrdering: false);
}
