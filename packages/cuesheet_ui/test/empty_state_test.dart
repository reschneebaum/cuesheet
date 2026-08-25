import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('says what the screen is for, not just that it is empty',
      (tester) async {
    await tester.pumpComponent(const EmptyState(
      title: 'Nothing queued',
      body: 'Choose an episode and pick what should happen to it.',
    ));

    expect(find.text('Nothing queued'), findsOneWidget);
    expect(find.textContaining('pick what should happen'), findsOneWidget);
  });

  testWidgets('an action is optional', (tester) async {
    await tester.pumpComponent(const EmptyState(title: 'Nothing queued'));
    expect(tester.takeException(), isNull);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('a section header can carry an action', (tester) async {
    await tester.pumpComponent(SectionHeader(
      label: 'Recently replaced',
      trailing: TextButton(onPressed: () {}, child: const Text('Clear')),
    ));

    expect(find.text('RECENTLY REPLACED'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
  });

  testWidgets('both render in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpComponent(
        const Column(children: [
          SectionHeader(label: 'Up next'),
          EmptyState(title: 'Nothing queued', body: 'Pick something.'),
        ]),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull, reason: '$brightness');
    }
  });
}
