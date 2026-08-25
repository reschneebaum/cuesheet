import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('shows the title and one line of metadata', (tester) async {
    await tester.pumpComponent(EpisodeRow(view: viewOf(), now: now));

    expect(find.text('The Mercator Problem'), findsOneWidget);
    expect(find.textContaining('The Cartographers'), findsOneWidget);
    expect(find.textContaining('1h'), findsOneWidget);
  });

  testWidgets('reports time remaining, not time elapsed', (tester) async {
    // The useful question part-way through is how much is left. Every app that
    // shows elapsed makes you do the subtraction.
    await tester.pumpComponent(EpisodeRow(
      view: viewOf(
        listening: ListeningState(
          episodeId: eid('e1'),
          position: const Duration(minutes: 20),
          startCount: 1,
          lastPlayedAt: now,
        ),
      ),
      now: now,
    ));

    expect(find.textContaining('40m left'), findsOneWidget);
  });

  testWidgets('says how far in when the feed gave no duration', (tester) async {
    await tester.pumpComponent(EpisodeRow(
      view: viewOf(
        duration: null,
        listening: ListeningState(
          episodeId: eid('e1'),
          position: const Duration(minutes: 12),
          startCount: 1,
          lastPlayedAt: now,
        ),
      ),
      now: now,
    ));

    expect(find.textContaining('12m in'), findsOneWidget);
  });

  testWidgets('a finished episode says so rather than showing 0m left',
      (tester) async {
    await tester.pumpComponent(EpisodeRow(
      view: viewOf(
        listening: ListeningState(
          episodeId: eid('e1'),
          position: const Duration(minutes: 60),
          playCount: 1,
          lastPlayedAt: now,
        ),
      ),
      now: now,
    ));

    expect(find.textContaining('Played'), findsOneWidget);
  });

  testWidgets('queue membership is on the row, not behind a tap',
      (tester) async {
    // §5.5. Learning the state of your own queue should not require opening
    // anything.
    await tester.pumpComponent(
        EpisodeRow(view: viewOf(), now: now, queuePosition: 3));

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('playing beats queued when an episode is both', (tester) async {
    await tester.pumpComponent(EpisodeRow(
      view: viewOf(),
      now: now,
      queuePosition: 1,
      isPlaying: true,
    ));

    expect(find.text('1'), findsNothing);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
  });

  testWidgets('an orphan is labelled rather than hidden', (tester) async {
    // §6, and the Phase 5 decision: an episode that silently vanishes is the
    // bug, not the label.
    await tester.pumpComponent(
        EpisodeRow(view: viewOf(orphaned: true), now: now));

    expect(find.text('NOT IN FEED'), findsOneWidget);
    expect(find.text('The Mercator Problem'), findsOneWidget);
  });

  testWidgets('drops the podcast name inside one podcast\'s own list',
      (tester) async {
    await tester.pumpComponent(
        EpisodeRow(view: viewOf(), now: now, showPodcast: false));

    expect(find.textContaining('The Cartographers'), findsNothing);
  });

  testWidgets('taps report, and a row with no handler is inert',
      (tester) async {
    var taps = 0;
    await tester.pumpComponent(
        EpisodeRow(view: viewOf(), now: now, onTap: () => taps++));
    await tester.tap(find.text('The Mercator Problem'));
    expect(taps, 1);
  });

  testWidgets('renders in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpComponent(
        EpisodeRow(view: viewOf(orphaned: true), now: now, queuePosition: 2),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull, reason: '$brightness');
      expect(find.text('NOT IN FEED'), findsOneWidget);
    }
  });
}
