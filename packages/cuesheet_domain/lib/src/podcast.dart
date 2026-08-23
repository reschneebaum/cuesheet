import 'package:freezed_annotation/freezed_annotation.dart';

import 'ids.dart';

part 'podcast.freezed.dart';

/// A subscribed feed.
///
/// [feedUrl] is unique but is deliberately not the identity — see
/// `docs/ARCHITECTURE.md` §6. Feeds move.
@freezed
abstract class Podcast with _$Podcast {
  const factory Podcast({
    required PodcastId id,
    required Uri feedUrl,
    required String title,
    String? author,
    Uri? artworkUrl,
    String? description,
    DateTime? lastFetchedAt,
  }) = _Podcast;
}
