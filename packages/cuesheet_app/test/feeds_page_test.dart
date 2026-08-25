import 'package:cuesheet_app/src/debug_app.dart';
import 'package:cuesheet_app/src/providers.dart';
import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_playback/cuesheet_playback.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const feedUrl = 'https://feeds.example.com/show.xml';

String feed(List<String> titles, {String? title = 'The Cartographers'}) => '''
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    ${title == null ? '' : '<title>$title</title>'}
    ${titles.map((t) => '''
    <item>
      <title>$t</title>
      <guid>guid-$t</guid>
      <pubDate>Tue, 10 Jun 2025 09:00:00 GMT</pubDate>
      <enclosure url="https://cdn.example.com/$t.mp3" type="audio/mpeg"/>
    </item>''').join()}
  </channel>
</rss>''';

/// Drives the real stack — real widgets, real repositories, real SQLite — with
/// the database in memory and the network replaced by canned responses. Two
/// `overrides` entries and no test in this file can reach the internet.
void main() {
  late CuesheetDatabase db;
  late FakeFeedTransport transport;
  late FakePodcastDirectory directory;
  late FakeAudioEngine engine;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpFeeds(WidgetTester tester) async {
    db = CuesheetDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    transport = FakeFeedTransport({feedUrl: feed(['One', 'Two'])});
    directory = FakePodcastDirectory([
      DirectoryResult(
        title: 'The Cartographers',
        feedUrl: Uri.parse(feedUrl),
        author: 'Wren Alvarez',
        primaryGenre: 'Science',
        episodeCount: 214,
      ),
    ]);

    engine = FakeAudioEngine();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        feedTransportProvider.overrideWithValue(transport),
        podcastDirectoryProvider.overrideWithValue(directory),
        audioEngineProvider.overrideWithValue(engine),
      ],
      child: const DebugApp(),
    ));
    await settle(tester);

    await tester.tap(find.text('Feeds'));
    await settle(tester);
  }

  void appTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      // Closed here rather than in a tearDown, for the same reason the unmount
      // is here: the database is closed after the body, and a still-open
      // engine stream keeps a listener alive across that boundary.
      await engine.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    });
  }

  Future<void> subscribeByUrl(WidgetTester tester, [String url = feedUrl]) async {
    await tester.enterText(find.byType(TextField).first, url);
    await tester.tap(find.text('Subscribe'));
    await settle(tester);
  }

  appTest('subscribing by URL ingests the feed and says what it did',
      (tester) async {
    await pumpFeeds(tester);
    expect(find.text('Nothing subscribed yet.'), findsOneWidget);

    await subscribeByUrl(tester);

    expect(find.textContaining('+2 new'), findsOneWidget);
    expect(find.text('The Cartographers'), findsOneWidget);
    expect(find.textContaining('2 episodes · fetched'), findsOneWidget);
  });

  appTest('a refresh that changed nothing says so, by rung', (tester) async {
    await pumpFeeds(tester);
    await subscribeByUrl(tester);

    await tester.tap(find.text('Refresh'));
    await settle(tester);

    expect(find.textContaining('+0 new, 2 matched (2 by guid)'),
        findsOneWidget);
  });

  appTest('a 304 is reported rather than looking like an empty feed',
      (tester) async {
    await pumpFeeds(tester);
    transport.etags[feedUrl] = 'W/"v1"';
    await subscribeByUrl(tester);

    await tester.tap(find.text('Refresh'));
    await settle(tester);

    expect(find.textContaining('not modified (304)'), findsOneWidget);
    expect(find.textContaining('2 episodes · fetched'), findsOneWidget);
  });

  appTest('an episode dropped from the feed is reported and orphaned',
      (tester) async {
    await pumpFeeds(tester);
    await subscribeByUrl(tester);

    // Give the second episode some history, so it is worth keeping.
    final second =
        (await db.select(db.episodes).get()).firstWhere((e) => e.title == 'Two');
    await DriftListeningRepository(db).save(ListeningState(
      episodeId: EpisodeId(second.id),
      position: const Duration(minutes: 4),
      startCount: 1,
      lastPlayedAt: DateTime.utc(2026, 8, 24),
    ));

    transport.bodies[feedUrl] = feed(['One']);
    await tester.tap(find.text('Refresh'));
    await settle(tester);

    expect(find.textContaining('1 matched (1 by guid), 1 orphaned'),
        findsOneWidget);
    expect(find.text('Subscriptions · 1 orphaned episodes'), findsOneWidget);
  });

  appTest('a URL that is not a feed leaves no subscription and says why',
      (tester) async {
    await pumpFeeds(tester);
    transport.bodies['https://nope.example/x'] = '<html>hello</html>';

    await subscribeByUrl(tester, 'https://nope.example/x');

    expect(find.textContaining('not a feed'), findsOneWidget);
    expect(find.text('Nothing subscribed yet.'), findsOneWidget);
  });

  appTest('an unreachable feed is distinguishable from a bad one',
      (tester) async {
    await pumpFeeds(tester);
    await subscribeByUrl(tester, 'https://missing.example/rss');

    expect(find.textContaining('gone: 404'), findsOneWidget);
  });

  appTest('text that is not a URL never reaches the transport', (tester) async {
    await pumpFeeds(tester);
    await subscribeByUrl(tester, 'the cartographers');

    expect(find.textContaining('is not a URL'), findsOneWidget);
    expect(transport.requested, isEmpty);
  });

  appTest('searching the directory offers a result to subscribe to',
      (tester) async {
    await pumpFeeds(tester);

    await tester.enterText(find.byType(TextField).at(1), 'cartographers');
    await tester.tap(find.text('Search'));
    await settle(tester);

    expect(find.text('Wren Alvarez · Science · 214 episodes'), findsOneWidget);

    await tester.tap(find.text('Subscribe').last);
    await settle(tester);

    expect(find.textContaining('+2 new'), findsOneWidget);
    expect(find.textContaining('2 episodes · fetched'), findsOneWidget);
  });

  appTest('a search with no matches says so', (tester) async {
    await pumpFeeds(tester);

    await tester.enterText(find.byType(TextField).at(1), 'nothing at all');
    await tester.tap(find.text('Search'));
    await settle(tester);

    expect(find.text('No results.'), findsOneWidget);
  });

  appTest('parser warnings reach the log', (tester) async {
    await pumpFeeds(tester);
    transport.bodies[feedUrl] = '''
<rss version="2.0"><channel><title>Ugly</title>
  <item><title>No Audio Here</title></item>
</channel></rss>''';

    await subscribeByUrl(tester);

    expect(find.textContaining('No Audio Here'), findsOneWidget);
  });

  group('what ingestion did, on the episode rows', () {
    Future<void> showEpisodes(WidgetTester tester) async {
      await tester.tap(find.text('Episodes'));
      await settle(tester);
    }

    appTest('a newly ingested episode says it was a first sighting',
        (tester) async {
      await pumpFeeds(tester);
      await subscribeByUrl(tester);
      await showEpisodes(tester);

      expect(find.textContaining('matched: firstSighting'), findsNWidgets(2));
    });

    appTest('after a refresh the rows say which rung attached them',
        (tester) async {
      await pumpFeeds(tester);
      await subscribeByUrl(tester);
      await tester.tap(find.text('Refresh'));
      await settle(tester);
      await showEpisodes(tester);

      // §6 rule 6: the column holds the most recent match, so a steady-state
      // refresh rewrites firstSighting to the rung that actually matched.
      expect(find.textContaining('matched: guid'), findsNWidgets(2));
      expect(find.textContaining('matched: firstSighting'), findsNothing);
    });

    appTest('an enclosure that moved reports the rung that rescued it',
        (tester) async {
      await pumpFeeds(tester);
      await subscribeByUrl(tester);

      // Same audio, new guids: the CMS migration case.
      transport.bodies[feedUrl] = feed(['One', 'Two'])
          .replaceAll('<guid>guid-', '<guid>rewritten-');
      await tester.tap(find.text('Refresh'));
      await settle(tester);
      await showEpisodes(tester);

      expect(find.textContaining('matched: enclosureUrl'), findsNWidgets(2));
    });

    appTest('an orphan is labelled rather than hidden', (tester) async {
      await pumpFeeds(tester);
      await subscribeByUrl(tester);

      final second = (await db.select(db.episodes).get())
          .firstWhere((e) => e.title == 'Two');
      await DriftListeningRepository(db).save(ListeningState(
        episodeId: EpisodeId(second.id),
        position: const Duration(minutes: 4),
        startCount: 1,
        lastPlayedAt: DateTime.utc(2026, 8, 24),
      ));

      transport.bodies[feedUrl] = feed(['One']);
      await tester.tap(find.text('Refresh'));
      await settle(tester);
      await showEpisodes(tester);

      // Hidden in the real UI later (§6); shown here, because the whole
      // question the harness answers is whether ingestion did the right thing.
      expect(find.text('NOT IN FEED'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
    });

    appTest('the podcast dropdown narrows the list to one show',
        (tester) async {
      await pumpFeeds(tester);
      await subscribeByUrl(tester);

      const other = 'https://feeds.example.com/other.xml';
      transport.bodies[other] =
          feed(['Three'], title: 'Nightshift Radio');
      await subscribeByUrl(tester, other);
      await showEpisodes(tester);

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Three'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<PodcastId?>));
      await settle(tester);
      await tester.tap(find.text('Nightshift Radio').last);
      await settle(tester);

      expect(find.text('Three'), findsOneWidget);
      expect(find.text('One'), findsNothing);
    });
  });
}
