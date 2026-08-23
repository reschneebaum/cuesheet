import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:test/test.dart';

EpisodeId e(String id) => EpisodeId(id);

List<EpisodeId> eps(String ids) =>
    ids.split(' ').where((s) => s.isNotEmpty).map(e).toList();

QueueState queueOf(
  String ids, {
  int position = 0,
  PlaybackSource? source = const FromQueue(),
  CuesheetKind kind = CuesheetKind.ephemeral,
}) =>
    QueueState(
      active: Cuesheet(
        id: const CuesheetId('existing'),
        kind: kind,
        items: eps(ids),
        title: kind == CuesheetKind.saved ? 'Saved' : null,
      ),
      position: position,
      source: source,
    );

IntentPreview preview(QueueState s, PlaybackIntent i, {String visible = 'a b c d'}) =>
    previewIntent(s, i, eps(visible));

void main() {
  // The whole reason previewIntent exists. If these two ever disagree, the UI
  // is promising something applyIntent will not do.
  group('agrees with applyIntent about whether anything will happen', () {
    final states = <String, QueueState>{
      'empty': QueueState.empty,
      'playing b': queueOf('a b c', position: 1),
      'idle queue': queueOf('a b c', source: null),
      'detached': queueOf('a b c', source: const Detached(EpisodeId('z'))),
      'saved queue': queueOf('a b c', kind: CuesheetKind.saved),
    };

    final intents = <String, PlaybackIntent>{
      'PlayJustThis(b)': PlayJustThis(e('b')),
      'PlayJustThis(z)': PlayJustThis(e('z')),
      'PlayFromHere(b, asc)': PlayFromHere(e('b'), TraversalOrder.ascending),
      'PlayFromHere(c, desc)': PlayFromHere(e('c'), TraversalOrder.descending),
      'PlayFromHere(absent)': PlayFromHere(e('zzz'), TraversalOrder.ascending),
      'InsertNext(a)': InsertNext(e('a')),
      'InsertNext(b)': InsertNext(e('b')),
      'AppendToQueue(c)': AppendToQueue(e('c')),
      'AppendToQueue(new)': AppendToQueue(e('new')),
      'MoveToEnd(a)': MoveToEnd(e('a')),
      'MoveToEnd(c)': MoveToEnd(e('c')),
      'MoveToEnd(absent)': MoveToEnd(e('zzz')),
      'ReplaceQueue(x y)': ReplaceQueue(eps('x y')),
      'ReplaceQueue(empty)': const ReplaceQueue([]),
      'RemoveFromQueue(a)': RemoveFromQueue(e('a')),
      'RemoveFromQueue(absent)': RemoveFromQueue(e('zzz')),
      'ReorderQueue(0 -> 2)': const ReorderQueue(from: 0, to: 2),
      'ReorderQueue(out of range)': const ReorderQueue(from: 9, to: 0),
    };

    for (final MapEntry(key: stateName, value: state) in states.entries) {
      for (final MapEntry(key: intentName, value: intent) in intents.entries) {
        test('$stateName / $intentName', () {
          bool actuallyChanges;
          try {
            actuallyChanges = applyIntent(state, intent, eps('a b c d'),
                    newCuesheetId: () => const CuesheetId('x'))
                .changed;
          } on ArgumentError {
            actuallyChanges = false;
          }

          expect(preview(state, intent).willChange, actuallyChanges);
        });
      }
    }
  });

  group('AppendToQueue', () {
    test('names the position when the episode is already queued', () {
      final p = preview(queueOf('a b c'), AppendToQueue(e('b')));

      expect(p.willChange, isFalse);
      expect(p.verb, 'Add to queue');
      expect(p.detail, 'Already #2 in queue');
    });

    test('offers plainly when the episode is not queued', () {
      final p = preview(queueOf('a b c'), AppendToQueue(e('new')));

      expect(p.willChange, isTrue);
      expect(p.detail, isNull);
    });
  });

  group('MoveToEnd', () {
    test('is offered for a queued episode that is not last', () {
      final p = preview(queueOf('a b c'), MoveToEnd(e('a')));

      expect(p.willChange, isTrue);
      expect(p.verb, 'Move to end');
      expect(p.detail, isNull);
    });

    test('explains itself when the episode is already last', () {
      final p = preview(queueOf('a b c'), MoveToEnd(e('c')));

      expect(p.willChange, isFalse);
      expect(p.detail, 'Already last');
    });

    test('explains itself when the episode is not queued', () {
      final p = preview(queueOf('a b c'), MoveToEnd(e('zzz')));

      expect(p.willChange, isFalse);
      expect(p.detail, 'Not in queue');
    });
  });

  group('PlayFromHere', () {
    test('distinguishes direction and counts what it would queue', () {
      final down = preview(QueueState.empty,
          PlayFromHere(e('b'), TraversalOrder.ascending));
      final up = preview(QueueState.empty,
          PlayFromHere(e('b'), TraversalOrder.descending));

      expect(down.verb, 'Play from here down');
      expect(down.detail, '3 episodes');
      expect(up.verb, 'Play from here up');
      expect(up.detail, '2 episodes');
    });

    test('says so rather than throwing when the episode is not in the list', () {
      final p = preview(QueueState.empty,
          PlayFromHere(e('zzz'), TraversalOrder.ascending));

      expect(p.willChange, isFalse);
      expect(p.detail, 'Not in this list');
    });

    test('counts one episode in the singular', () {
      final p = preview(QueueState.empty,
          PlayFromHere(e('d'), TraversalOrder.ascending));

      expect(p.detail, '1 episode');
    });
  });

  group('InsertNext', () {
    test('says nothing to do for the episode already playing', () {
      final p = preview(queueOf('a b c', position: 1), InsertNext(e('b')));

      expect(p.willChange, isFalse);
      expect(p.verb, 'Play next');
      expect(p.detail, 'Playing now');
    });

    test('says nothing to do for the episode already next', () {
      final p = preview(queueOf('a b c', position: 1), InsertNext(e('c')));

      expect(p.willChange, isFalse);
      expect(p.detail, 'Already next');
    });

    test('flags that a queued episode would be moved, not added', () {
      final p = preview(queueOf('a b c d', position: 2), InsertNext(e('a')));

      expect(p.willChange, isTrue);
      expect(p.detail, 'Move up from #1');
    });
  });

  group('PlayJustThis', () {
    test('says nothing to do when already playing detached', () {
      final p = preview(
        queueOf('a b c', source: const Detached(EpisodeId('z'))),
        PlayJustThis(e('z')),
      );

      expect(p.willChange, isFalse);
      expect(p.detail, 'Playing now');
    });

    test('is offered even for an episode already in the queue', () {
      // Playing b from the queue; "play just this" still means something
      // different — it detaches, so finishing will not advance the queue.
      final p = preview(queueOf('a b c', position: 1), PlayJustThis(e('b')));

      expect(p.willChange, isTrue);
      expect(p.detail, isNull);
    });
  });

  group('ReplaceQueue', () {
    test('counts what it would replace the queue with', () {
      final p = preview(queueOf('a b c'), ReplaceQueue(eps('x y z')));

      expect(p.verb, 'Replace queue');
      expect(p.detail, '3 episodes');
    });
  });
}
