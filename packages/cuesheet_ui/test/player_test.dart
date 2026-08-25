import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('Artwork', () {
    testWidgets('reserves its space even with nothing to show', (tester) async {
      await tester.pumpComponent(
          const Artwork(url: null, size: 120, title: 'The Cartographers'));

      final box = tester.getSize(find.byType(Artwork));
      expect(box.width, 120);
      expect(box.height, 120);
    });

    testWidgets('falls back to an initial when there is no image',
        (tester) async {
      await tester.pumpComponent(
          const Artwork(url: null, size: 120, title: 'The Cartographers'));
      expect(find.text('T'), findsOneWidget);
    });

    testWidgets('an untitled placeholder is a mark, not a blank', (tester) async {
      await tester.pumpComponent(const Artwork(url: null, size: 64));
      expect(find.byIcon(Icons.podcasts), findsOneWidget);
    });

    testWidgets('a URL that will not load falls back rather than throwing',
        (tester) async {
      // Network images fail under `flutter test`, which is exactly the path
      // worth asserting: a feed's artwork host going down must not take a list
      // with it.
      await tester.pumpComponent(Artwork(
        url: Uri.parse('https://nope.example/cover.jpg'),
        size: 64,
        title: 'Nightshift',
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Artwork), findsOneWidget);
    });
  });

  group('Scrubber', () {
    testWidgets('shows elapsed on the left and remaining on the right',
        (tester) async {
      await tester.pumpComponent(Scrubber(
        position: const Duration(seconds: 70),
        duration: const Duration(minutes: 30),
        onSeek: (_) {},
      ));

      expect(find.text('01:10'), findsOneWidget);
      expect(find.text('-28:50'), findsOneWidget);
    });

    testWidgets('seeks once, on release', (tester) async {
      // Seeking on every frame of a drag would have the engine chasing the
      // finger across the file.
      final seeks = <Duration>[];
      await tester.pumpComponent(Scrubber(
        position: Duration.zero,
        duration: const Duration(minutes: 10),
        onSeek: seeks.add,
      ));

      await tester.drag(find.byType(Slider), const Offset(200, 0));
      await tester.pump();

      expect(seeks, hasLength(1));
      expect(seeks.single, greaterThan(Duration.zero));
    });

    testWidgets('a drag is not yanked back by an incoming position',
        (tester) async {
      // The engine reports five times a second and has not been told about the
      // drag yet.
      Duration? sought;
      await tester.pumpComponent(Scrubber(
        position: Duration.zero,
        duration: const Duration(minutes: 10),
        onSeek: (d) => sought = d,
      ));

      final slider = tester.getCenter(find.byType(Slider));
      final gesture = await tester.startGesture(slider);
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();

      final duringDrag =
          tester.widget<Slider>(find.byType(Slider)).value;
      expect(duringDrag, greaterThan(0));

      // A tick lands mid-drag, reporting the old position.
      await tester.pumpComponent(Scrubber(
        position: const Duration(seconds: 1),
        duration: const Duration(minutes: 10),
        onSeek: (d) => sought = d,
      ));
      expect(tester.widget<Slider>(find.byType(Slider)).value, duringDrag);

      await gesture.up();
      await tester.pump();
      expect(sought, isNotNull);
    });

    testWidgets('an unknown length leaves the track inert but visible',
        (tester) async {
      await tester.pumpComponent(Scrubber(
        position: const Duration(seconds: 30),
        duration: null,
        onSeek: (_) {},
      ));

      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(find.text('--:--'), findsOneWidget);
      expect(find.text('00:30'), findsOneWidget);
    });
  });

  group('TransportControls', () {
    testWidgets('labels the skip intervals rather than making you learn them',
        (tester) async {
      await tester.pumpComponent(TransportControls(
        isPlaying: false,
        onPlayPause: () {},
        onBack: () {},
        onForward: () {},
      ));

      expect(find.text('15'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
    });

    testWidgets('the play control reflects and reports', (tester) async {
      var taps = 0;
      await tester.pumpComponent(TransportControls(
        isPlaying: true,
        onPlayPause: () => taps++,
        onBack: () {},
        onForward: () {},
      ));

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pause_rounded));
      expect(taps, 1);
    });

    testWidgets('offers no next-track control at all', (tester) async {
      // The queue is edited by named intents. A pair of arrows that silently
      // move the playhead off what you were listening to has nowhere to say
      // "and it stays where it was".
      await tester.pumpComponent(TransportControls(
        isPlaying: false,
        onPlayPause: () {},
        onBack: () {},
        onForward: () {},
      ));

      expect(find.byIcon(Icons.skip_next), findsNothing);
      expect(find.byIcon(Icons.skip_previous), findsNothing);
    });

    testWidgets('disables cleanly with nothing loaded', (tester) async {
      await tester.pumpComponent(TransportControls(
        isPlaying: false,
        enabled: false,
        onPlayPause: () {},
        onBack: () {},
        onForward: () {},
      ));

      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton,
                Icons.play_arrow_rounded))
            .onPressed,
        isNull,
      );
    });
  });

  group('SpeedButton', () {
    testWidgets('says the current rate and reports a new one', (tester) async {
      final chosen = <double>[];
      await tester.pumpComponent(
          SpeedButton(speed: 1.0, onChanged: chosen.add));

      expect(find.text('1×'), findsOneWidget);
      await tester.tap(find.text('1×'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5×').last);
      await tester.pumpAndSettle();

      expect(chosen.single, 1.5);
    });
  });

  testWidgets('the player renders in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpComponent(
        Column(children: [
          const Artwork(url: null, size: 100, title: 'X'),
          Scrubber(
            position: const Duration(seconds: 5),
            duration: const Duration(minutes: 1),
            onSeek: (_) {},
          ),
          TransportControls(
            isPlaying: true,
            onPlayPause: () {},
            onBack: () {},
            onForward: () {},
          ),
        ]),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull, reason: '$brightness');
    }
  });
}
