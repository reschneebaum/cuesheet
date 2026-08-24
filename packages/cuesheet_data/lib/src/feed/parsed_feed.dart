import 'package:meta/meta.dart';

/// What one fetch of a feed said, before anything has been decided about
/// identity.
///
/// Deliberately not a [Podcast]: a parsed feed has no `PodcastId`, because ids
/// are assigned by the matcher (§6) and not by the feed. Keeping the two types
/// apart is what stops feed-supplied data from ever being mistaken for
/// identity.
@immutable
final class ParsedFeed {
  const ParsedFeed({
    required this.items,
    this.title,
    this.author,
    this.description,
    this.artworkUrl,
    this.warnings = const [],
  });

  /// Null when the channel has no usable `<title>`. The parser does not invent
  /// one — the caller knows the feed URL and can fall back to something
  /// meaningful; the parser cannot.
  final String? title;
  final String? author;
  final String? description;
  final Uri? artworkUrl;
  final List<ParsedItem> items;

  /// Non-fatal complaints: items dropped, fields that would not parse.
  ///
  /// These exist to be shown, not swallowed. "Why is that episode missing?" is
  /// a question the debug harness should be able to answer without a
  /// breakpoint.
  final List<String> warnings;

  @override
  String toString() =>
      'ParsedFeed($title, ${items.length} items, ${warnings.length} warnings)';
}

/// One `<item>`, normalized but not yet identified.
@immutable
final class ParsedItem {
  const ParsedItem({
    required this.title,
    required this.enclosureUrl,
    required this.feedPosition,
    this.guid,
    this.publishedAt,
    this.duration,
    this.description,
    this.artworkUrl,
  });

  final String title;
  final Uri enclosureUrl;

  /// Index among the feed's `<item>` elements, counting the ones that were
  /// dropped. Positions therefore have gaps where an item was unusable, which
  /// is correct: this is where the episode sits in the feed, not where it sits
  /// in our list.
  final int feedPosition;

  /// Trimmed, and null when the feed supplied an empty one. Never trusted as
  /// identity — only as the first rung of the ladder (§6).
  final String? guid;
  final DateTime? publishedAt;
  final Duration? duration;

  /// As the feed wrote it, HTML and all. See `plain_text.dart`.
  final String? description;
  final Uri? artworkUrl;

  @override
  String toString() => 'ParsedItem(#$feedPosition $title)';
}

/// The feed is not a feed. Distinct from a feed that is merely bad: everything
/// recoverable is a warning on [ParsedFeed] instead.
final class FeedFormatException implements Exception {
  const FeedFormatException(this.message);

  final String message;

  @override
  String toString() => 'FeedFormatException: $message';
}
