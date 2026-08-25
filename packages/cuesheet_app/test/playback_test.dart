import 'package:cuesheet_app/src/debug_app.dart';
import 'package:cuesheet_app/src/now_playing_page.dart';
import 'package:cuesheet_app/src/providers.dart';
import 'package:cuesheet_app/src/transport_bar.dart';
import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_playback/cuesheet_playback.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Playback driven through the real stack: real widgets, real repositories,
/// real SQLite, real `onTick`. Only the engine is fake, and only because a
/// plugin cannot run under `flutter test` at all.
void main() {
  late CuesheetDatabase db;
  late FakeAudioEngine engine;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    db = CuesheetDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    engine = FakeAudioEngine();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioEngineProvider.overrideWithValue(engine),
      ],
      child: const DebugApp(),
    ));
    await settle(tester);
    await tester.tap(find.text('Seed data'));
    await settle(tester);
  }

  /// Pumps the app and seeds it before every body, so no test can forget to.
  void appTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      await pumpApp(tester);
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await engine.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    });
  }

  Future<void> intentOn(
    WidgetTester tester,
    int index,
    String label,
  ) async {
    await tester.tap(find.byType(EpisodeTile).at(index));
    await settle(tester);
    await tester.tap(find.text(label));
    await settle(tester);
  }

  Future<ListeningState> listeningFor(EpisodeId id) =>
      DriftListeningRepository(db).byEpisode(id);

  appTest('nothing plays until an intent says so', (tester) async {
    // The app opening and immediately making noise is the surprise this whole
    // project reacts against.
    expect(engine.calls, isEmpty);
    expect(find.text('Nothing loaded'), findsOneWidget);
  });

  appTest('play from here loads the first episode and starts it',
      (tester) async {
    await intentOn(tester, 0, 'Play from here down');

    expect(engine.loaded, isNotNull);
    expect(engine.status, PlaybackStatus.playing);
    expect(engine.calls.where((c) => c == 'play'), hasLength(1));
  });

  appTest('the transport reflects the engine, not the stored playhead',
      (tester) async {
    // The database is written on a five-second debounce (§9). Both elapses
    // below are well inside it, so if the bar moves it is reading ticks.
    await intentOn(tester, 0, 'Play from here down');

    String countdown() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((d) => d.contains('-0') || d.contains('-1'),
            orElse: () => '');

    engine.elapse(const Duration(seconds: 1));
    await settle(tester);
    final first = countdown();

    engine.elapse(const Duration(seconds: 2));
    await settle(tester);
    final second = countdown();

    expect(first, isNotEmpty);
    expect(second, isNot(first));
  });

  appTest('pause writes the playhead immediately', (tester) async {
    await intentOn(tester, 0, 'Play from here down');
    final playing = engine.loaded!.id;

    engine.elapse(const Duration(seconds: 90));
    await settle(tester);

    await tester.tap(find.byTooltip('Pause'));
    await settle(tester);

    // §9: forced on pause, not left to the debounce.
    expect((await listeningFor(playing)).position,
        const Duration(seconds: 90));
    expect(engine.status, PlaybackStatus.paused);
  });

  appTest('finishing advances the queue and plays the next episode',
      (tester) async {
    await intentOn(tester, 0, 'Play from here down');
    final first = engine.loaded!.id;

    engine.finish();
    await settle(tester);

    expect(engine.loaded!.id, isNot(first));
    expect(engine.status, PlaybackStatus.playing);

    await tester.tap(find.text('Queue'));
    await settle(tester);
    expect(find.text('#2 of 18'), findsOneWidget);
  });

  appTest('the finished episode stays in the queue', (tester) async {
    // Rule 1: finishing is not an intent, so it does not get to mutate the
    // queue. The playhead moves; the document does not shrink.
    await intentOn(tester, 0, 'Play from here down');
    engine.finish();
    await settle(tester);

    await tester.tap(find.text('Queue'));
    await settle(tester);
    expect(find.text('#2 of 18'), findsOneWidget);
  });

  appTest('finishing counts the play and stamps the episode', (tester) async {
    await intentOn(tester, 0, 'Play from here down');
    final first = engine.loaded!.id;

    engine.finish();
    await settle(tester);

    final state = await listeningFor(first);
    expect(state.playCount, 1);
    expect(state.finishedAt, isNotNull);
  });

  appTest('a detached episode that ends stops instead of resuming the queue',
      (tester) async {
    // §5.3, end to end. The decision that makes "play just this" safe.
    await intentOn(tester, 0, 'Play from here down');
    final queued = engine.loaded!.id;

    await intentOn(tester, 2, 'Play just this');
    final detached = engine.loaded!.id;
    expect(detached, isNot(queued));

    engine.finish();
    await settle(tester);

    expect(engine.status, PlaybackStatus.idle);
    expect(engine.calls.last, 'stop');

    await tester.tap(find.text('Queue'));
    await settle(tester);
    // Untouched: still eighteen items, still on the first.
    expect(find.textContaining('#1 of 18'), findsOneWidget);
  });

  appTest('a detached listen is still recorded', (tester) async {
    await intentOn(tester, 2, 'Play just this');
    final detached = engine.loaded!.id;
    final before = (await listeningFor(detached)).playCount;

    engine.finish();
    await settle(tester);

    expect((await listeningFor(detached)).playCount, before + 1);
  });

  appTest('replaying a finished episode starts it over', (tester) async {
    // Resuming at the stored position would put the playhead inside the finish
    // threshold, the engine would report completion immediately, and a queue of
    // already-heard episodes would advance through itself as fast as it could
    // load them.
    await intentOn(tester, 0, 'Play from here down');
    final first = engine.loaded!.id;
    engine.finish();
    await settle(tester);

    // Play it again, on its own.
    await intentOn(tester, 0, 'Play just this');

    expect(engine.loaded!.id, first);
    expect(engine.position, Duration.zero);
    expect(engine.calls.last, 'play');
  });

  appTest('seeking moves the engine and is written through', (tester) async {
    await intentOn(tester, 0, 'Play from here down');
    final playing = engine.loaded!.id;
    engine.elapse(const Duration(minutes: 5));
    await settle(tester);

    await tester.tap(find.byTooltip('Back 15s'));
    await settle(tester);

    expect(engine.position, const Duration(minutes: 4, seconds: 45));
    expect((await listeningFor(playing)).position,
        const Duration(minutes: 4, seconds: 45));
  });

  appTest('the play button toggles', (tester) async {
    await intentOn(tester, 0, 'Play from here down');

    await tester.tap(find.byTooltip('Pause'));
    await settle(tester);
    expect(engine.status, PlaybackStatus.paused);

    await tester.tap(find.byTooltip('Play'));
    await settle(tester);
    expect(engine.status, PlaybackStatus.playing);
  });

  appTest('reaching the end of the queue stops rather than wrapping',
      (tester) async {
    // "Play from here up" from the second row runs backwards through the list,
    // giving a queue of exactly two.
    await intentOn(tester, 1, 'Play from here up');
    await tester.tap(find.text('Queue'));
    await settle(tester);
    expect(find.text('#1 of 2'), findsOneWidget);

    engine.finish();
    await settle(tester);
    engine.finish();
    await settle(tester);

    expect(engine.calls.last, 'stop');
    await tester.tap(find.text('Queue'));
    await settle(tester);
    expect(find.textContaining('Reached the end'), findsOneWidget);
  });

  group('now playing', () {
    Future<void> openPlayer(WidgetTester tester) async {
      await tester.tap(find.byType(TransportBar));
      await settle(tester);
    }

    appTest('the mini bar is inert until something is loaded', (tester) async {
      expect(find.text('Nothing loaded'), findsOneWidget);
      await openPlayer(tester);
      // No route pushed: there is nothing to look at.
      expect(find.byType(NowPlayingPage), findsNothing);
    });

    appTest('opens from the mini bar and names what is playing',
        (tester) async {
      await intentOn(tester, 0, 'Play from here down');
      final title = engine.loaded!.title;

      await openPlayer(tester);

      expect(find.byType(NowPlayingPage), findsOneWidget);
      expect(find.text(title), findsWidgets);
      expect(find.textContaining('From the queue · #1 of 18'), findsOneWidget);
    });

    appTest('says when playback will not carry on into the queue',
        (tester) async {
      // §5.3 on the surface where it matters most: the difference between
      // "this continues into your queue" and "this does not".
      await intentOn(tester, 0, 'Play from here down');
      await intentOn(tester, 2, 'Play just this');
      await openPlayer(tester);

      expect(find.textContaining('queue untouched'), findsOneWidget);
      expect(find.textContaining('From the queue'), findsNothing);
    });

    appTest('scrubbing moves the playhead and writes it through',
        (tester) async {
      await intentOn(tester, 0, 'Play from here down');
      final playing = engine.loaded!.id;
      await openPlayer(tester);

      await tester.drag(find.byType(Slider), const Offset(120, 0));
      await settle(tester);

      expect(engine.position, greaterThan(Duration.zero));
      // §9 forces a write on seek rather than leaving it to the debounce.
      expect((await listeningFor(playing)).position, engine.position);
    });

    appTest('the player offers the same intents as anywhere else',
        (tester) async {
      await intentOn(tester, 0, 'Play from here down');
      await openPlayer(tester);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await settle(tester);

      expect(find.text('Play just this'), findsOneWidget);
      expect(find.text('Move to end'), findsOneWidget);
    });

    appTest('closes back to where it was opened from', (tester) async {
      await intentOn(tester, 0, 'Play from here down');
      await openPlayer(tester);

      expect(find.byTooltip('Close'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      await settle(tester);

      expect(find.byType(NowPlayingPage), findsNothing);
      expect(find.byType(TransportBar), findsOneWidget);
    });
  });
}
