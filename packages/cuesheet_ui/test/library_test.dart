import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Podcast podcastOf({
  String title = 'The Cartographers',
  String? author = 'Wren Alvarez',
  DateTime? lastFetchedAt,
  String? description,
}) =>
    Podcast(
      id: const PodcastId('p1'),
      feedUrl: Uri.parse('https://feeds.example.com/show.xml'),
      title: title,
      author: author,
      lastFetchedAt: lastFetchedAt,
      description: description,
    );

void main() {
  group('PodcastTile', () {
    testWidgets('leads with artwork and names the show', (tester) async {
      await tester.pumpComponent(
          SizedBox(width: 160, child: PodcastTile(podcast: podcastOf())));

      expect(find.byType(Artwork), findsOneWidget);
      expect(find.text('The Cartographers'), findsOneWidget);
    });

    testWidgets('says nothing at all when a subscription is caught up',
        (tester) async {
      // A zero is worse than silence: it is a number you have to read before
      // discovering it means "nothing to do".
      await tester.pumpComponent(
          SizedBox(width: 160, child: PodcastTile(podcast: podcastOf())));

      expect(find.textContaining('unplayed'), findsNothing);
    });

    testWidgets('counts unplayed episodes when there are any', (tester) async {
      await tester.pumpComponent(SizedBox(
        width: 160,
        child: PodcastTile(podcast: podcastOf(), unplayed: 12),
      ));

      expect(find.text('12 unplayed'), findsOneWidget);
    });
  });

  group('PodcastHeader', () {
    testWidgets('shows the show, the author and what we know about it',
        (tester) async {
      await tester.pumpComponent(PodcastHeader(
        podcast: podcastOf(lastFetchedAt: now.subtract(const Duration(days: 3))),
        description: 'Conversations about maps.',
        now: now,
        episodeCount: 214,
        unplayed: 9,
      ));

      expect(find.text('The Cartographers'), findsOneWidget);
      expect(find.text('Wren Alvarez'), findsOneWidget);
      expect(find.textContaining('214 episodes'), findsOneWidget);
      expect(find.textContaining('9 unplayed'), findsOneWidget);
      expect(find.textContaining('checked 3 days ago'), findsOneWidget);
    });

    testWidgets('collapses a long description and expands it on tap',
        (tester) async {
      const long = 'One. Two. Three. Four. Five. Six. Seven. Eight. Nine. '
          'Ten. Eleven. Twelve. Thirteen. Fourteen. Fifteen. Sixteen.';
      await tester.pumpComponent(SizedBox(
        width: 300,
        child: PodcastHeader(
          podcast: podcastOf(),
          description: long,
          now: now,
        ),
      ));

      Text description() => tester.widget<Text>(find.text(long));
      expect(description().maxLines, 4);

      await tester.tap(find.text(long));
      await tester.pump();
      expect(description().maxLines, isNull);
    });

    testWidgets('a refresh control reports and disables while working',
        (tester) async {
      var refreshes = 0;
      await tester.pumpComponent(PodcastHeader(
        podcast: podcastOf(),
        description: null,
        now: now,
        onRefresh: () => refreshes++,
      ));

      await tester.tap(find.text('Check for new'));
      expect(refreshes, 1);

      await tester.pumpComponent(PodcastHeader(
        podcast: podcastOf(),
        description: null,
        now: now,
        refreshing: true,
        onRefresh: () => refreshes++,
      ));
      expect(find.text('Checking…'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Checking…'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('renders in both themes', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpComponent(
          PodcastHeader(
            podcast: podcastOf(),
            description: 'Maps.',
            now: now,
            episodeCount: 3,
          ),
          brightness: brightness,
        );
        expect(tester.takeException(), isNull, reason: '$brightness');
      }
    });
  });
}
