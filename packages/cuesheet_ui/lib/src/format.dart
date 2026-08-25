import 'package:cuesheet_domain/cuesheet_domain.dart';

/// Clock time, for a scrubber or a timecode.
String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// How long something is, said the way a person would say it.
///
/// A list row wants "1h 2m", not "01:02:03" — the reader is deciding whether
/// they have time for this, not following along.
String formatLength(Duration? d) {
  if (d == null) return 'unknown length';
  if (d.inMinutes < 1) return 'under a minute';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// What a row says about how far in you are.
///
/// Reports remaining rather than elapsed, deliberately: the useful question
/// part-way through an episode is how much is left, and every app that shows
/// elapsed makes you do the subtraction.
String describeProgress(
  ListeningState listening, {
  required Duration? episodeDuration,
  required DateTime now,
}) {
  final state = listenStateOf(
    listening,
    episodeDuration: episodeDuration,
    now: now,
  );

  return switch (state) {
    ListenState.unplayed => formatLength(episodeDuration),
    ListenState.started => switch (remaining(listening,
          episodeDuration: episodeDuration)) {
        // Started an episode whose length the feed never gave us. Saying how
        // far in is the only honest thing left.
        null => '${formatLength(listening.position)} in',
        final left => '${formatLength(left)} left',
      },
    ListenState.finished => 'Played',
    ListenState.relistenCandidate => 'Played, a while ago',
  };
}

/// Short, and relative only where relative is genuinely easier to read.
///
/// "3 days ago" stops helping somewhere around a fortnight, at which point a
/// date is both shorter and more use.
String formatPublished(DateTime? at, {required DateTime now}) {
  if (at == null) return '';
  final age = now.difference(at);
  if (age.isNegative) return _shortDate(at, now);
  if (age.inHours < 1) return 'just now';
  if (age.inHours < 24) return '${age.inHours}h ago';
  if (age.inDays == 1) return 'yesterday';
  if (age.inDays < 14) return '${age.inDays} days ago';
  return _shortDate(at, now);
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _shortDate(DateTime at, DateTime now) {
  final local = at.toLocal();
  final month = _months[local.month - 1];
  return local.year == now.toLocal().year
      ? '${local.day} $month'
      : '${local.day} $month ${local.year}';
}

/// Joins the parts of a metadata line, dropping the ones that are empty rather
/// than leaving a run of separators behind.
String metaLine(List<String?> parts) =>
    parts.where((p) => p != null && p.isNotEmpty).join(' · ');
