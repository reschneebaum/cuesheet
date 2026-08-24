import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'decode_body.dart';

/// What one conditional fetch returned.
sealed class FeedFetch {
  const FeedFetch();
}

/// The server said 304: nothing has changed since the stored validators, and
/// there is no body to parse. The cheapest possible refresh, and the reason
/// `etag` and `lastModified` are columns at all.
final class FeedUnchanged extends FeedFetch {
  const FeedUnchanged();
}

@immutable
final class FeedBody extends FeedFetch {
  const FeedBody({required this.body, this.etag, this.lastModified});

  final String body;

  /// Handed back on the next fetch. Stored verbatim, including the weak
  /// validator prefix (`W/"…"`) if the server sent one — rewriting a validator
  /// is how you end up never getting a 304 again.
  final String? etag;
  final String? lastModified;
}

/// The bytes-and-headers boundary.
///
/// Declared here rather than in `cuesheet_domain` because conditional requests
/// are a fact about HTTP, not about podcasts. It exists so that not one test
/// in this package touches the network.
abstract interface class FeedTransport {
  Future<FeedFetch> fetch(Uri url, {String? etag, String? lastModified});
}

/// A fetch that did not produce a feed. Carries the status code when there was
/// one, because "404" and "the wifi is off" want different words in the UI.
final class FeedTransportException implements Exception {
  const FeedTransportException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// The feed is gone for good rather than temporarily unreachable.
  bool get isPermanent => statusCode == 404 || statusCode == 410;

  @override
  String toString() => 'FeedTransportException($statusCode): $message';
}

class HttpFeedTransport implements FeedTransport {
  HttpFeedTransport({http.Client? client, this.userAgent = 'Cuesheet/0.1'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String userAgent;

  @override
  Future<FeedFetch> fetch(Uri url, {String? etag, String? lastModified}) async {
    final http.Response response;
    try {
      response = await _client.get(url, headers: {
        'user-agent': userAgent,
        'accept': 'application/rss+xml, application/xml;q=0.9, */*;q=0.8',
        // Null-aware elements: the entry is omitted entirely when the value
        // is null, rather than sent as an empty header.
        'if-none-match': ?etag,
        'if-modified-since': ?lastModified,
      });
    } on Object catch (e) {
      throw FeedTransportException('could not reach $url: $e');
    }

    if (response.statusCode == 304) return const FeedUnchanged();
    if (response.statusCode != 200) {
      throw FeedTransportException(
        'unexpected status fetching $url',
        statusCode: response.statusCode,
      );
    }

    return FeedBody(
      // Not `response.body`: that decodes by the Content-Type charset and
      // falls back to Latin-1, which mangles the many feeds served as
      // `text/xml` with no charset at all. See `decodeFeedBody`.
      body: decodeFeedBody(
        response.bodyBytes,
        contentType: response.headers['content-type'],
      ),
      etag: response.headers['etag'],
      lastModified: response.headers['last-modified'],
    );
  }
}

/// A transport that answers from a map of canned responses.
///
/// Lives in `lib/` rather than `test/` on purpose: the debug harness uses it
/// to drive ingestion against the fixture corpus with no network, which is the
/// same thing the tests want.
class FakeFeedTransport implements FeedTransport {
  FakeFeedTransport(
    Map<String, String> bodies, {
    Map<String, String> etags = const {},
  })  : bodies = {...bodies},
        etags = {...etags};

  /// Copied rather than held, so both stay mutable however they were passed.
  /// A fake you cannot reconfigure between the two halves of a test — serve
  /// this, now serve that — is not much of a fake.
  final Map<String, String> bodies;
  final Map<String, String> etags;

  /// Every fetch, in order, with the validators it was given — so a test can
  /// assert that the second refresh actually sent back the etag it stored.
  final List<({Uri url, String? etag, String? lastModified})> requested = [];

  /// Set to have the next fetch throw, for testing the unreachable path.
  FeedTransportException? failWith;

  @override
  Future<FeedFetch> fetch(Uri url, {String? etag, String? lastModified}) async {
    requested.add((url: url, etag: etag, lastModified: lastModified));
    if (failWith != null) throw failWith!;

    final body = bodies[url.toString()];
    if (body == null) {
      throw const FeedTransportException('no canned response', statusCode: 404);
    }

    final current = etags[url.toString()];
    if (current != null && current == etag) return const FeedUnchanged();

    return FeedBody(body: body, etag: current);
  }
}
