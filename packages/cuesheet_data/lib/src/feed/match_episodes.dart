import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:meta/meta.dart';

import '../normalize_url.dart';
import '../tables.dart';
import 'parsed_feed.dart';

/// An episode already on file, reduced to the columns the ladder looks at.
///
/// Deliberately not an [Episode]: the matcher must be runnable without a
/// database, and taking the whole entity would invite it to read fields that
/// have nothing to do with identity.
@immutable
final class ExistingEpisode {
  const ExistingEpisode({
    required this.id,
    required this.normalizedEnclosureUrl,
    required this.title,
    this.guid,
    this.publishedAt,
  });

  final EpisodeId id;
  final String? guid;
  final String normalizedEnclosureUrl;
  final String title;
  final DateTime? publishedAt;
}

/// One incoming item, resolved to an episode id.
@immutable
final class MatchedItem {
  const MatchedItem({
    required this.item,
    required this.id,
    required this.rung,
  });

  final ParsedItem item;
  final EpisodeId id;

  /// How this item found its row. Stored on the episode, because when identity
  /// bugs surface the first question is always "how did this match?" and the
  /// answer should be in the database rather than reconstructed (§6 rule 4).
  final MatchRung rung;

  bool get isNew => rung == MatchRung.firstSighting;

  @override
  String toString() => 'MatchedItem(${id.value} via ${rung.name})';
}

@immutable
final class FeedMatch {
  const FeedMatch({required this.items, required this.vanished});

  final List<MatchedItem> items;

  /// Episodes on file that this fetch of the feed did not mention.
  ///
  /// Reported, not acted on. Whether a vanished episode is deleted or kept as
  /// an orphan depends on what else references it, which is a question for the
  /// ingestion — not for a pure function over one feed.
  final List<EpisodeId> vanished;

  Iterable<MatchedItem> get newEpisodes => items.where((i) => i.isNew);
}

/// Walks the identity ladder of §6 for a whole feed at once.
///
/// The rungs, in order, first hit wins:
///   1. `guid`, trimmed
///   2. normalized enclosure URL
///   3. title, normalized, plus publication date to day resolution
///
/// Pure, and given its id generator, so a test can assert on exact ids.
///
/// **An existing row is claimed at most once.** Two feed items that would both
/// match the same row is not hypothetical — a feed that republishes an episode
/// under a new guid while leaving the old item in place produces exactly that
/// — and letting both claim it would silently merge two episodes into one and
/// take the listening history of whichever won. The second item falls through
/// to the next rung instead, and to a new row if nothing else fits.
FeedMatch matchFeedItems({
  required Iterable<ExistingEpisode> existing,
  required Iterable<ParsedItem> incoming,
  required String Function() newId,
}) {
  final byGuid = <String, List<ExistingEpisode>>{};
  final byUrl = <String, List<ExistingEpisode>>{};
  final byTitleAndDay = <String, List<ExistingEpisode>>{};

  for (final row in existing) {
    final guid = row.guid?.trim();
    if (guid != null && guid.isNotEmpty) {
      (byGuid[guid] ??= []).add(row);
    }
    (byUrl[row.normalizedEnclosureUrl] ??= []).add(row);
    final key = _titleAndDayKey(row.title, row.publishedAt);
    if (key != null) (byTitleAndDay[key] ??= []).add(row);
  }

  final claimed = <String>{};
  final matched = <MatchedItem>[];

  ExistingEpisode? firstUnclaimed(List<ExistingEpisode>? candidates) {
    if (candidates == null) return null;
    for (final candidate in candidates) {
      if (!claimed.contains(candidate.id.value)) return candidate;
    }
    return null;
  }

  for (final item in incoming) {
    final guid = item.guid?.trim();
    final titleKey = _titleAndDayKey(item.title, item.publishedAt);

    final (ExistingEpisode?, MatchRung) hit = switch ((
      guid == null || guid.isEmpty ? null : firstUnclaimed(byGuid[guid]),
      firstUnclaimed(byUrl[normalizeEnclosureUrl(item.enclosureUrl)]),
      titleKey == null ? null : firstUnclaimed(byTitleAndDay[titleKey]),
    )) {
      (final row?, _, _) => (row, MatchRung.guid),
      (_, final row?, _) => (row, MatchRung.enclosureUrl),
      (_, _, final row?) => (row, MatchRung.titleAndDate),
      _ => (null, MatchRung.firstSighting),
    };

    final (row, rung) = hit;
    if (row != null) claimed.add(row.id.value);

    matched.add(MatchedItem(
      item: item,
      id: row?.id ?? EpisodeId(newId()),
      rung: rung,
    ));
  }

  return FeedMatch(
    items: matched,
    vanished: [
      for (final row in existing)
        if (!claimed.contains(row.id.value)) row.id,
    ],
  );
}

/// The third rung's key, or null when the item cannot supply one.
///
/// Both halves are required. Title alone would be catastrophic on the feeds
/// that most need a third rung: "Episode 42", "Bonus", and "Introduction"
/// recur, and matching on them would hand one episode's listening history to
/// another. Day resolution rather than the full timestamp because feeds
/// re-stamp items when they are edited.
String? _titleAndDayKey(String title, DateTime? publishedAt) {
  if (publishedAt == null) return null;
  final normalized = title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return null;
  final day = publishedAt.toUtc();
  return '$normalized@${day.year}-${day.month}-${day.day}';
}
