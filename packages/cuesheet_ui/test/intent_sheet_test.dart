import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const visible = [EpisodeId('e1'), EpisodeId('e2'), EpisodeId('e3')];

Widget sheetFor(
  QueueState queue, {
  String episode = 'e2',
  ValueChanged<PlaybackIntent>? onChosen,
}) =>
    IntentSheet(
      episodeTitle: 'Contour Lines',
      intents: episodeIntents(EpisodeId(episode)),
      queue: queue,
      visible: visible,
      onChosen: onChosen ?? (_) {},
    );

void main() {
  testWidgets('every label is the domain\'s, not the sheet\'s', (tester) async {
    // The anti-drift guarantee, asserted rather than trusted. If anyone ever
    // hardcodes a verb here, or invents a label for a new intent, this fails.
    final queue = queueOf(['e1', 'e2'], position: 0);
    await tester.pumpComponent(sheetFor(queue));

    for (final intent in episodeIntents(const EpisodeId('e2'))) {
      final preview = previewIntent(queue, intent, visible);
      expect(find.text(preview.verb), findsWidgets,
          reason: 'missing label for $intent');
      if (preview.detail != null) {
        expect(find.text(preview.detail!), findsWidgets,
            reason: 'missing detail for $intent');
      }
    }
  });

  testWidgets('an intent that would change nothing is shown, not hidden',
      (tester) async {
    // Hiding it would make the queue's state something you remember instead of
    // something you read.
    await tester.pumpComponent(sheetFor(queueOf(['e1', 'e2'], position: 0)));

    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Already #2 in queue'), findsOneWidget);
  });

  testWidgets('a satisfied intent cannot be tapped', (tester) async {
    // A control that says "Add to queue" and then does nothing has lied.
    final chosen = <PlaybackIntent>[];
    await tester.pumpComponent(sheetFor(
      queueOf(['e1', 'e2'], position: 0),
      onChosen: chosen.add,
    ));

    await tester.tap(find.text('Add to queue'));
    await tester.pump();
    expect(chosen, isEmpty);
  });

  testWidgets('an applicable intent reports the intent itself', (tester) async {
    final chosen = <PlaybackIntent>[];
    await tester.pumpComponent(sheetFor(
      const QueueState(),
      onChosen: chosen.add,
    ));

    await tester.tap(find.text('Add to queue'));
    await tester.pump();
    // Compared by type and field: the intents are sealed values but carry no
    // `==`, since nothing in the domain ever needs to compare two of them —
    // `Cuesheet` deliberately excludes `origin` from its own equality (§10).
    expect(
      chosen.single,
      isA<AppendToQueue>()
          .having((i) => i.episode, 'episode', const EpisodeId('e2')),
    );
  });

  testWidgets('offers move-to-end beside add, never instead of it',
      (tester) async {
    // They are different things to want (§5.1), and swapping one for the other
    // behind the reader's back is the surprise the sheet exists to prevent.
    await tester.pumpComponent(sheetFor(queueOf(['e1', 'e2'], position: 0)));

    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Move to end'), findsOneWidget);
  });

  testWidgets('names the episode it is about to act on', (tester) async {
    // The row that opened the sheet may well be behind the sheet.
    await tester.pumpComponent(sheetFor(const QueueState()));
    expect(find.text('Contour Lines'), findsOneWidget);
  });

  testWidgets('both directions of play-from-here are offered', (tester) async {
    await tester.pumpComponent(sheetFor(const QueueState()));
    expect(find.text('Play from here down'), findsOneWidget);
    expect(find.text('Play from here up'), findsOneWidget);
  });

  testWidgets('an episode outside the visible list says so', (tester) async {
    await tester.pumpComponent(sheetFor(const QueueState(), episode: 'zz'));
    expect(find.text('Not in this list'), findsWidgets);
  });

  testWidgets('renders in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpComponent(
        sheetFor(queueOf(['e1', 'e2'])),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull, reason: '$brightness');
    }
  });
}
