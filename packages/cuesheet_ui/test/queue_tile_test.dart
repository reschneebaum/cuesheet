import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('numbers from one, because nobody counts a running order from zero',
      (tester) async {
    await tester.pumpComponent(QueueTile(view: viewOf(), index: 0, now: now));
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('the playing entry shows the playhead instead of its number',
      (tester) async {
    await tester.pumpComponent(
        QueueTile(view: viewOf(), index: 4, now: now, isPlaying: true));

    expect(find.text('5'), findsNothing);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
  });

  testWidgets('entries behind the playhead are dimmed, not removed',
      (tester) async {
    // Rule 1 made visible: finishing is not an intent, so the episode stays and
    // the playhead moves past it. The cuesheet is a document you have read part
    // of.
    await tester.pumpComponent(Column(children: [
      QueueTile(
          view: viewOf(id: 'a', title: 'Behind'),
          index: 0,
          now: now,
          isBehindPlayhead: true),
      QueueTile(view: viewOf(id: 'b', title: 'Ahead'), index: 1, now: now),
    ]));

    final colors = CuesheetColors.light;
    Color colorOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;

    expect(find.text('Behind'), findsOneWidget);
    expect(colorOf('Behind'), colors.inkMuted);
    expect(colorOf('Ahead'), colors.ink);
  });

  testWidgets('the playing entry is never dimmed, even once passed',
      (tester) async {
    await tester.pumpComponent(QueueTile(
      view: viewOf(title: 'Now'),
      index: 0,
      now: now,
      isPlaying: true,
      isBehindPlayhead: true,
    ));

    expect(tester.widget<Text>(find.text('Now')).style!.color,
        CuesheetColors.light.ink);
  });

  testWidgets('takes its drag affordance from whoever owns the list',
      (tester) async {
    // cuesheet_ui never learns that ReorderableListView exists.
    await tester.pumpComponent(QueueTile(
      view: viewOf(),
      index: 0,
      now: now,
      handle: const Icon(Icons.drag_handle),
    ));

    expect(find.byIcon(Icons.drag_handle), findsOneWidget);
  });

  testWidgets('renders in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpComponent(
        QueueTile(view: viewOf(), index: 2, now: now, isBehindPlayhead: true),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull, reason: '$brightness');
    }
  });
}
