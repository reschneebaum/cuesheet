import 'package:freezed_annotation/freezed_annotation.dart';

part 'directory.freezed.dart';

/// Finding a podcast to subscribe to.
///
/// Declared here and implemented outward (§3, §12). v1 implements it against
/// Apple's iTunes Search API — keyless, no signup, adequate coverage. Podcast
/// Index has richer metadata and can be swapped in later without anything
/// above this line noticing, which is the point of the interface existing at
/// all rather than the app calling a URL.
abstract interface class PodcastDirectory {
  /// Ordered by the directory's own relevance. An empty or blank query
  /// returns an empty list rather than everything.
  Future<List<DirectoryResult>> search(String query);
}

/// One row of search results.
///
/// Deliberately not a [Podcast]: nothing here has a `PodcastId`, because
/// nothing here is subscribed. The only field that survives subscription is
/// [feedUrl] — everything else is re-read from the feed itself, which is the
/// authority. A directory that is out of date must not be able to write a
/// stale title into the library.
@freezed
abstract class DirectoryResult with _$DirectoryResult {
  const factory DirectoryResult({
    required String title,
    required Uri feedUrl,
    String? author,
    Uri? artworkUrl,
    String? primaryGenre,

    /// As the directory last counted them. Indicative, not authoritative.
    int? episodeCount,
    DateTime? lastReleaseAt,
  }) = _DirectoryResult;
}

/// The directory could not be searched. Distinct from a search that found
/// nothing, which is an empty list and not an error.
final class DirectoryException implements Exception {
  const DirectoryException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'DirectoryException($statusCode): $message';
}
