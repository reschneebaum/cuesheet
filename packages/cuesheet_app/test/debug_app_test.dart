import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_playback/cuesheet_playback.dart';
import 'package:cuesheet_app/src/debug_app.dart';
import 'package:cuesheet_app/src/intent_menu.dart';
import 'package:cuesheet_app/src/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real stack — real widgets, real repositories, real SQLite —
/// with only the database swapped for an in-memory one. That single
/// `overrides` entry is the payoff for wiring every dependency in one place.
void main() {
  late CuesheetDatabase db;
  late FakeAudioEngine engine;

  /// Bounded pumping instead of `pumpAndSettle`.
  ///
  /// `pumpAndSettle` waits for the frame scheduler to go quiet, so anything
  /// that animates or emits forever hangs it until a ten-minute timeout. A
  /// fixed number of short pumps drains microtasks, lets stream events land,
  /// and covers the popup-menu transition, without ever being able to hang.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    db = CuesheetDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // Plugins do not work under `flutter test` — there is no engine and no
    // channel to answer — so the fake is not a convenience here, it is the
    // only way the app runs at all.
    engine = FakeAudioEngine();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioEngineProvider.overrideWithValue(engine),
      ],
      child: const DebugApp(),
    ));
    await settle(tester);
  }

  Future<void> seed(WidgetTester tester) async {
    await tester.tap(find.text('Seed data'));
    await settle(tester);
  }

  Future<void> openMenuOnFirstEpisode(WidgetTester tester) async {
    await tester.tap(find.byType(IntentMenu).first);
    await settle(tester);
  }

  /// Wraps [testWidgets] so the tree is unmounted inside the test body.
  ///
  /// Disposing the ProviderScope cancels drift's query streams, and drift
  /// defers its bookkeeping with a zero-duration `Timer`. The test binding
  /// asserts no timers are pending once the tree is gone, and that check runs
  /// *before* any `addTearDown` callback — so the unmount has to happen here,
  /// with a pump afterwards to let the timer actually fire.
  void appTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      // Closed here rather than in a tearDown, for the same reason the unmount
      // is here: the database is closed after the body, and a still-open
      // engine stream keeps a listener alive across that boundary.
      await engine.dispose();
      // A duration, not a bare pump: `pump()` with no argument schedules a
      // frame without advancing the fake clock, so a Timer(Duration.zero)
      // never comes due.
      await tester.pump(const Duration(milliseconds: 1));
    });
  }

  appTest('starts empty and fills from the seeder', (tester) async {
    await pumpApp(tester);
    expect(find.text('Nothing matches.'), findsOneWidget);

    await seed(tester);
    expect(find.text('Cuesheet debug · 18 episodes'), findsOneWidget);
  });

  appTest('play from here builds a queue out of the visible list',
      (tester) async {
    await pumpApp(tester);
    await seed(tester);

    await openMenuOnFirstEpisode(tester);
    await tester.tap(find.text('Play from here down'));
    await settle(tester);

    await tester.tap(find.text('Queue'));
    await settle(tester);

    expect(find.text('Position 1 of 18'), findsOneWidget);
  });

  appTest('play just this leaves the queue alone', (tester) async {
    await pumpApp(tester);
    await seed(tester);

    // Build a queue first.
    await openMenuOnFirstEpisode(tester);
    await tester.tap(find.text('Play from here down'));
    await settle(tester);

    // Then play one episode outside it.
    await tester.tap(find.byType(IntentMenu).at(3));
    await settle(tester);
    await tester.tap(find.text('Play just this'));
    await settle(tester);

    await tester.tap(find.text('Queue'));
    await settle(tester);

    // The whole point of detached playback, asserted through the UI.
    expect(find.textContaining('Playing detached'), findsOneWidget);
    expect(
      find.text('The queue is untouched and will not advance.'),
      findsOneWidget,
    );
  });

  appTest('the menu reports what it will not do, rather than hiding it',
      (tester) async {
    await pumpApp(tester);
    await seed(tester);

    await openMenuOnFirstEpisode(tester);
    // Nothing is queued yet, so these two have nothing to do and say so.
    expect(find.text('Not in queue'), findsNWidgets(2)); // MoveToEnd, Remove
    await tester.tap(find.text('Add to queue'));
    await settle(tester);

    await openMenuOnFirstEpisode(tester);
    expect(find.text('Already #1 in queue'), findsOneWidget);
  });

  appTest('replacing a queue keeps the old one recoverable',
      (tester) async {
    await pumpApp(tester);
    await seed(tester);

    await openMenuOnFirstEpisode(tester);
    await tester.tap(find.text('Play from here down'));
    await settle(tester);

    await tester.tap(find.byType(IntentMenu).at(2));
    await settle(tester);
    await tester.tap(find.text('Play from here up'));
    await settle(tester);

    await tester.tap(find.text('Queue'));
    await settle(tester);

    expect(find.text('Position 1 of 3'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await settle(tester);
    expect(find.text('Position 1 of 18'), findsOneWidget);
  });

  appTest('undo puts the queue back', (tester) async {
    await pumpApp(tester);
    await seed(tester);

    await openMenuOnFirstEpisode(tester);
    await tester.tap(find.text('Play from here down'));
    await settle(tester);

    await tester.tap(find.text('Queue'));
    await settle(tester);
    expect(find.text('Undo (1)'), findsOneWidget);

    await tester.tap(find.text('Undo (1)'));
    await settle(tester);

    expect(find.text('The queue is empty.'), findsOneWidget);
    expect(find.text('Undo (0)'), findsOneWidget);
  });

  appTest('filtering by listen state narrows the list', (tester) async {
    await pumpApp(tester);
    await seed(tester);

    await tester.tap(find.text('Relisten'));
    await settle(tester);

    // The seeder puts exactly one episode past the relisten window.
    expect(find.byType(IntentMenu), findsOneWidget);
  });
}
