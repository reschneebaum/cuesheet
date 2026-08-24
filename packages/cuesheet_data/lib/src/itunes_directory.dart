import 'dart:convert';

import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:http/http.dart' as http;

/// [PodcastDirectory] over Apple's iTunes Search API.
///
/// Keyless and requires no signup, which is the whole reason it is the v1
/// choice (§12). The interface is what matters; this is the cheapest thing
/// that satisfies it.
class ITunesPodcastDirectory implements PodcastDirectory {
  ITunesPodcastDirectory({
    http.Client? client,
    this.country = 'US',
    this.limit = 25,
    this.userAgent = 'Cuesheet/0.1',
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// The store to search. Results differ by storefront: a show that is not
  /// distributed in one country simply will not appear there.
  final String country;
  final int limit;
  final String userAgent;

  static final _endpoint = Uri.https('itunes.apple.com', '/search');

  @override
  Future<List<DirectoryResult>> search(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];

    final url = _endpoint.replace(queryParameters: {
      'term': term,
      'media': 'podcast',
      'entity': 'podcast',
      'country': country,
      'limit': '$limit',
    });

    final http.Response response;
    try {
      response = await _client.get(url, headers: {'user-agent': userAgent});
    } on Object catch (e) {
      throw DirectoryException('could not reach the directory: $e');
    }

    if (response.statusCode != 200) {
      throw DirectoryException(
        'directory search failed',
        statusCode: response.statusCode,
      );
    }

    return parseITunesSearch(utf8.decode(response.bodyBytes, allowMalformed: true));
  }
}

/// Split out from the client so the mapping is testable against a captured
/// response with no HTTP involved at all.
List<DirectoryResult> parseITunesSearch(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    throw DirectoryException('directory returned malformed JSON: ${e.message}');
  }

  if (decoded is! Map<String, Object?>) {
    throw const DirectoryException('directory returned an unexpected shape');
  }

  final results = decoded['results'];
  if (results is! List) return const [];

  return [
    for (final entry in results)
      if (entry is Map<String, Object?>) ?_toResult(entry),
  ];
}

DirectoryResult? _toResult(Map<String, Object?> json) {
  // Apple omits feedUrl on some rows — usually shows that have been pulled
  // from distribution. There is nothing to subscribe to, so there is no row.
  final feedUrl = _uri(json['feedUrl']);
  if (feedUrl == null) return null;

  final title = _string(json['collectionName']) ??
      _string(json['trackName']) ??
      _string(json['artistName']);
  if (title == null) return null;

  return DirectoryResult(
    title: title,
    feedUrl: feedUrl,
    author: _string(json['artistName']),
    // Largest first. The 30px variant exists and is unusable.
    artworkUrl: _uri(json['artworkUrl600']) ??
        _uri(json['artworkUrl100']) ??
        _uri(json['artworkUrl60']),
    primaryGenre: _string(json['primaryGenreName']),
    episodeCount: json['trackCount'] is int ? json['trackCount']! as int : null,
    lastReleaseAt: _dateTime(json['releaseDate']),
  );
}

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Uri? _uri(Object? value) {
  final text = _string(value);
  if (text == null) return null;
  final parsed = Uri.tryParse(text);
  return parsed == null || !parsed.hasScheme || parsed.host.isEmpty
      ? null
      : parsed;
}

DateTime? _dateTime(Object? value) {
  final text = _string(value);
  return text == null ? null : DateTime.tryParse(text)?.toUtc();
}

/// A directory that answers from a fixed list, for the debug harness and for
/// tests that care about what happens after a search rather than during one.
class FakePodcastDirectory implements PodcastDirectory {
  FakePodcastDirectory(this.results);

  final List<DirectoryResult> results;
  final List<String> queries = [];

  @override
  Future<List<DirectoryResult>> search(String query) async {
    queries.add(query);
    if (query.trim().isEmpty) return const [];
    final needle = query.toLowerCase();
    return [
      for (final r in results)
        if (r.title.toLowerCase().contains(needle) ||
            (r.author?.toLowerCase().contains(needle) ?? false))
          r,
    ];
  }
}
