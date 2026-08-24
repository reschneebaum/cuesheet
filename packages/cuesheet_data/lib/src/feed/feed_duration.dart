/// `<itunes:duration>` is specified as either a plain number of seconds or a
/// colon-separated clock. Both arrive, along with several things that are
/// neither.
///
/// Two colon-separated parts are always `mm:ss`, never `hh:mm`. A feed that
/// means ninety minutes writes `90:00`, and reading that as ninety hours would
/// be a silent, enormous error — the kind that only surfaces when a
/// `DurationBetween` filter (§8) quietly stops returning an episode.
Duration? parseFeedDuration(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;

  final parts = text.split(':');
  if (parts.length > 3) return null;

  var seconds = 0.0;
  for (final part in parts) {
    final value = double.tryParse(part.trim());
    if (value == null || value.isNaN || value.isNegative) return null;
    seconds = seconds * 60 + value;
  }

  // A feed that says `0` or `00:00` does not know the duration; it is not
  // claiming the episode is empty. Reporting null says the same thing without
  // making every consumer special-case zero.
  if (seconds <= 0 || seconds.isInfinite) return null;

  return Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());
}
