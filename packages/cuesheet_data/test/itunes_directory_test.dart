import 'dart:convert';
import 'dart:io';

import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final capturedResponse =
    File('test/fixtures/itunes_search.json').readAsStringSync();

/// Serves one canned response and records what was asked for.
({MockClient client, List<Uri> requested}) serving(
  String body, {
  int status = 200,
}) {
  final requested = <Uri>[];
  return (
    client: MockClient((request) async {
      requested.add(request.url);
      return http.Response(body, status,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }),
    requested: requested,
  );
}

void main() {
  group('mapping a captured response', () {
    late List<DirectoryResult> results;
    setUp(() => results = parseITunesSearch(capturedResponse));

    test('maps the fields the app actually needs', () {
      final first = results.first;
      expect(first.title, 'The Cartographers');
      expect(first.author, 'Wren Alvarez');
      expect(first.feedUrl, Uri.parse('https://feeds.cartographers.example/rss'));
      expect(first.primaryGenre, 'Science');
      expect(first.episodeCount, 214);
      expect(first.lastReleaseAt, DateTime.utc(2025, 6, 10, 9));
    });

    test('takes the largest artwork available', () {
      expect(results.first.artworkUrl,
          Uri.parse('https://is1.example/600x600bb.jpg'));
      expect(results.last.artworkUrl,
          Uri.parse('https://is3.example/60x60bb.jpg'));
    });

    test('drops rows with no feed URL, blank included', () {
      // Nothing to subscribe to, so nothing to show. Apple omits feedUrl on
      // shows pulled from distribution.
      expect(results.map((r) => r.title),
          ['The Cartographers', 'Ampersand & Co']);
    });

    test('survives missing and unparseable optional fields', () {
      final second = results.last;
      expect(second.episodeCount, isNull);
      expect(second.lastReleaseAt, isNull);
      expect(second.primaryGenre, 'Comedy');
    });
  });

  group('malformed responses', () {
    test('an empty results array is an empty list, not an error', () {
      expect(parseITunesSearch('{"resultCount":0,"results":[]}'), isEmpty);
    });

    test('a missing results key is an empty list', () {
      expect(parseITunesSearch('{"resultCount":0}'), isEmpty);
    });

    test('JSON that is not an object throws', () {
      expect(() => parseITunesSearch('[1,2,3]'),
          throwsA(isA<DirectoryException>()));
    });

    test('text that is not JSON throws', () {
      expect(() => parseITunesSearch('<html>502</html>'),
          throwsA(isA<DirectoryException>()));
    });
  });

  group('the request', () {
    test('asks for podcasts, in the configured storefront', () async {
      final (:client, :requested) = serving(capturedResponse);
      await ITunesPodcastDirectory(client: client, country: 'GB', limit: 5)
          .search('cartographers');

      final url = requested.single;
      expect(url.host, 'itunes.apple.com');
      expect(url.queryParameters, {
        'term': 'cartographers',
        'media': 'podcast',
        'entity': 'podcast',
        'country': 'GB',
        'limit': '5',
      });
    });

    test('a blank query does not hit the network at all', () async {
      final (:client, :requested) = serving(capturedResponse);
      final directory = ITunesPodcastDirectory(client: client);

      expect(await directory.search(''), isEmpty);
      expect(await directory.search('   '), isEmpty);
      expect(requested, isEmpty);
    });

    test('trims the query before sending it', () async {
      final (:client, :requested) = serving(capturedResponse);
      await ITunesPodcastDirectory(client: client).search('  maps  ');
      expect(requested.single.queryParameters['term'], 'maps');
    });

    test('a non-200 throws, carrying the status', () async {
      final (:client, requested: _) = serving('', status: 503);
      await expectLater(
        ITunesPodcastDirectory(client: client).search('maps'),
        throwsA(isA<DirectoryException>()
            .having((e) => e.statusCode, 'statusCode', 503)),
      );
    });

    test('an unreachable directory throws rather than returning nothing',
        () async {
      final client = MockClient((_) async => throw const SocketException('no'));
      await expectLater(
        ITunesPodcastDirectory(client: client).search('maps'),
        throwsA(isA<DirectoryException>()
            .having((e) => e.statusCode, 'statusCode', isNull)),
      );
    });

    test('decodes UTF-8 regardless of what the header claims', () async {
      final body = jsonEncode({
        'results': [
          {'collectionName': 'Café Ampersand', 'feedUrl': 'https://x.example/f'}
        ]
      });
      final client = MockClient((_) async => http.Response.bytes(
            utf8.encode(body),
            200,
            headers: {'content-type': 'text/javascript'},
          ));
      final results = await ITunesPodcastDirectory(client: client).search('c');
      expect(results.single.title, 'Café Ampersand');
    });
  });

  test('the fake directory filters on title and author', () async {
    final directory = FakePodcastDirectory([
      DirectoryResult(
          title: 'The Cartographers',
          feedUrl: Uri.parse('https://a.example/f'),
          author: 'Wren Alvarez'),
      DirectoryResult(
          title: 'Nightshift Radio', feedUrl: Uri.parse('https://b.example/f')),
    ]);

    expect((await directory.search('cart')).single.title, 'The Cartographers');
    expect((await directory.search('wren')).single.title, 'The Cartographers');
    expect(await directory.search('nothing'), isEmpty);
    expect(await directory.search(''), isEmpty);
    expect(directory.queries, ['cart', 'wren', 'nothing', '']);
  });
}
