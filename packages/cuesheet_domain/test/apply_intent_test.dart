import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers. These tests are the specification for the intent algebra, so the
// helpers stay dumb and obvious on purpose.
// ---------------------------------------------------------------------------

EpisodeId e(String id) => EpisodeId(id);

List<EpisodeId> eps(String ids) =>
    ids.split(' ').where((s) => s.isNotEmpty).map(e).toList();

/// Deterministic identifier source, so expected values can name the cuesheet
/// an intent is going to create.
CuesheetId Function() sequentialIds() {
  var n = 0;
  return () => CuesheetId('new-${++n}');
}

QueueState queueOf(
  String ids, {
  int position = 0,
  PlaybackSource? source = const FromQueue(),
  CuesheetKind kind = CuesheetKind.ephemeral,
  String sheetId = 'existing',
}) =>
    QueueState(
      active: Cuesheet(
        id: CuesheetId(sheetId),
        kind: kind,
        items: eps(ids),
        title: kind == CuesheetKind.saved ? 'Saved' : null,
      ),
      position: position,
      source: source,
    );

IntentResult apply(
  QueueState state,
  PlaybackIntent intent, {
  String visible = '',
  CuesheetId Function()? ids,
}) =>
    applyIntent(
      state,
      intent,
      eps(visible),
      newCuesheetId: ids ?? sequentialIds(),
    );

/// Invariants that must hold for every state the algebra ever produces.
void expectValid(QueueState s) {
  final sheet = s.active;
  if (sheet != null) {
    expect(
      sheet.items.length,
      sheet.items.toSet().length,
      reason: 'no cuesheet may contain an episode twice',
    );
    if (sheet.items.isNotEmpty) {
      expect(s.position, inInclusiveRange(0, sheet.items.length - 1),
          reason: 'position must index a real item');
    } else {
      expect(s.position, 0, reason: 'empty queue must sit at position 0');
      expect(s.source, isNot(isA<FromQueue>()),
          reason: 'cannot be playing from an empty queue');
    }
  }
}

void main() {
  // -------------------------------------------------------------------------
  group('PlayJustThis', () {
    test('detaches playback and leaves the queue completely untouched', () {
      final before = queueOf('a b c', position: 1);
      final r = apply(before, PlayJustThis(e('z')));

      expect(r.changed, isTrue);
      expect(r.state.source, const Detached(EpisodeId('z')));
      expect(r.state.nowPlaying, e('z'));
      // The whole point: the queue and our place in it survive verbatim.
      expect(r.state.active, before.active);
      expect(r.state.position, 1);
      expect(r.displaced, isNull);
      expectValid(r.state);
    });

    test('is a no-op when that episode is already playing detached', () {
      final before = queueOf('a b c', position: 1, source: const Detached(EpisodeId('z')));
      final r = apply(before, PlayJustThis(e('z')));

      expect(r.changed, isFalse);
      expect(r.state, before);
    });

    test('works when there is no queue at all', () {
      final r = apply(QueueState.empty, PlayJustThis(e('z')));

      expect(r.changed, isTrue);
      expect(r.state.nowPlaying, e('z'));
      expect(r.state.active, isNull);
      expectValid(r.state);
    });
  });

  // -------------------------------------------------------------------------
  group('PlayFromHere ascending', () {
    test('queues the tapped episode through the end of the visible list', () {
      final r = apply(
        QueueState.empty,
        PlayFromHere(e('c'), TraversalOrder.ascending),
        visible: 'a b c d e',
      );

      expect(r.state.active!.items, eps('c d e'));
      expect(r.state.position, 0);
      expect(r.state.source, const FromQueue());
      expect(r.state.nowPlaying, e('c'));
      expectValid(r.state);
    });

    test('tapping the last item yields a single-episode cuesheet', () {
      final r = apply(QueueState.empty,
          PlayFromHere(e('e'), TraversalOrder.ascending), visible: 'a b c d e');

      expect(r.state.active!.items, eps('e'));
    });
  });

  group('PlayFromHere descending', () {
    test('queues the tapped episode back to the start, in reverse', () {
      final r = apply(QueueState.empty,
          PlayFromHere(e('c'), TraversalOrder.descending), visible: 'a b c d e');

      expect(r.state.active!.items, eps('c b a'));
      expect(r.state.nowPlaying, e('c'));
      expectValid(r.state);
    });

    test('tapping the first item yields a single-episode cuesheet', () {
      final r = apply(QueueState.empty,
          PlayFromHere(e('a'), TraversalOrder.descending), visible: 'a b c d e');

      expect(r.state.active!.items, eps('a'));
    });
  });

  group('PlayFromHere', () {
    test('is relative to the visible list, not to any canonical feed order', () {
      // Same episode, same intent, a differently-ordered on-screen list.
      final feedOrder = apply(QueueState.empty,
          PlayFromHere(e('c'), TraversalOrder.ascending), visible: 'a b c d');
      final filtered = apply(QueueState.empty,
          PlayFromHere(e('c'), TraversalOrder.ascending), visible: 'd c a');

      expect(feedOrder.state.active!.items, eps('c d'));
      expect(filtered.state.active!.items, eps('c a'));
    });

    test('retains the ephemeral cuesheet it displaced', () {
      final before = queueOf('x y z', position: 2);
      final r = apply(before, PlayFromHere(e('a'), TraversalOrder.ascending),
          visible: 'a b');

      expect(r.displaced, before.active);
      expect(r.displaced!.items, eps('x y z'));
    });

    test('does not report a displacement when the previous queue was saved', () {
      final before = queueOf('x y z', kind: CuesheetKind.saved);
      final r = apply(before, PlayFromHere(e('a'), TraversalOrder.ascending),
          visible: 'a b');

      expect(r.displaced, isNull);
    });

    test('rejects an episode that is not in the visible list', () {
      expect(
        () => apply(QueueState.empty,
            PlayFromHere(e('zzz'), TraversalOrder.ascending), visible: 'a b c'),
        throwsArgumentError,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('AppendToQueue', () {
    test('adds to the end without disturbing the position', () {
      final r = apply(queueOf('a b c', position: 1), AppendToQueue(e('d')));

      expect(r.state.active!.items, eps('a b c d'));
      expect(r.state.position, 1);
      expect(r.state.nowPlaying, e('b'));
      expectValid(r.state);
    });

    test('is a no-op when the episode is already queued', () {
      final before = queueOf('a b c', position: 1);
      final r = apply(before, AppendToQueue(e('c')));

      expect(r.changed, isFalse);
      expect(r.state, before);
    });

    test('creates a queue when there is none, and does not start playback', () {
      final r = apply(QueueState.empty, AppendToQueue(e('a')));

      expect(r.state.active!.items, eps('a'));
      expect(r.state.source, isNull);
      expect(r.state.nowPlaying, isNull);
      expectValid(r.state);
    });

    test('never starts playback on an idle queue', () {
      final r = apply(queueOf('a b', source: null), AppendToQueue(e('c')));

      expect(r.state.source, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('InsertNext', () {
    test('lands immediately after the playing episode', () {
      final r = apply(queueOf('a b c', position: 0), InsertNext(e('d')));

      expect(r.state.active!.items, eps('a d b c'));
      expect(r.state.nowPlaying, e('a'));
      expectValid(r.state);
    });

    test('moves an already-queued episode rather than duplicating it', () {
      final r = apply(queueOf('a b c d', position: 0), InsertNext(e('d')));

      expect(r.state.active!.items, eps('a d b c'));
      expectValid(r.state);
    });

    test('keeps playing the same episode when moving one from behind it', () {
      // Playing c at index 2; pull a forward to play next.
      final r = apply(queueOf('a b c d', position: 2), InsertNext(e('a')));

      expect(r.state.active!.items, eps('b c a d'));
      expect(r.state.nowPlaying, e('c'));
      expectValid(r.state);
    });

    test('is a no-op for the episode already playing', () {
      final before = queueOf('a b c', position: 1);
      final r = apply(before, InsertNext(e('b')));

      expect(r.changed, isFalse);
      expect(r.state, before);
    });

    test('creates a queue when there is none, without starting playback', () {
      final r = apply(QueueState.empty, InsertNext(e('a')));

      expect(r.state.active!.items, eps('a'));
      expect(r.state.source, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('ReplaceQueue', () {
    test('swaps the items and honours startAt', () {
      final r = apply(queueOf('a b c'), ReplaceQueue(eps('x y z'), startAt: 2));

      expect(r.state.active!.items, eps('x y z'));
      expect(r.state.position, 2);
      expect(r.state.nowPlaying, e('z'));
      expectValid(r.state);
    });

    test('clamps an out-of-range startAt', () {
      final r = apply(QueueState.empty, ReplaceQueue(eps('x y'), startAt: 99));

      expect(r.state.position, 1);
      expectValid(r.state);
    });

    test('drops duplicates, keeping the first occurrence', () {
      final r = apply(QueueState.empty, ReplaceQueue(eps('x y x z y')));

      expect(r.state.active!.items, eps('x y z'));
      expectValid(r.state);
    });

    test('an empty replacement leaves nothing playing', () {
      final r = apply(queueOf('a b c'), ReplaceQueue(const []));

      expect(r.state.active!.items, isEmpty);
      expect(r.state.source, isNull);
      expectValid(r.state);
    });
  });

  // -------------------------------------------------------------------------
  group('RemoveFromQueue', () {
    test('shifts the position when removing an earlier episode', () {
      final r = apply(queueOf('a b c', position: 2), RemoveFromQueue(e('a')));

      expect(r.state.active!.items, eps('b c'));
      expect(r.state.nowPlaying, e('c'), reason: 'still playing the same thing');
      expectValid(r.state);
    });

    test('advances to the next episode when removing the current one', () {
      final r = apply(queueOf('a b c', position: 1), RemoveFromQueue(e('b')));

      expect(r.state.active!.items, eps('a c'));
      expect(r.state.position, 1);
      expect(r.state.nowPlaying, e('c'));
      expectValid(r.state);
    });

    test('falls back to the previous episode when removing the last one', () {
      final r = apply(queueOf('a b', position: 1), RemoveFromQueue(e('b')));

      expect(r.state.active!.items, eps('a'));
      expect(r.state.nowPlaying, e('a'));
      expectValid(r.state);
    });

    test('stops playback when the queue is emptied', () {
      final r = apply(queueOf('a', position: 0), RemoveFromQueue(e('a')));

      expect(r.state.active!.items, isEmpty);
      expect(r.state.source, isNull);
      expect(r.state.nowPlaying, isNull);
      expectValid(r.state);
    });

    test('leaves detached playback alone', () {
      final r = apply(
        queueOf('a b', source: const Detached(EpisodeId('z'))),
        RemoveFromQueue(e('a')),
      );

      expect(r.state.active!.items, eps('b'));
      expect(r.state.nowPlaying, e('z'));
      expectValid(r.state);
    });

    test('is a no-op for an episode that is not queued', () {
      final before = queueOf('a b c', position: 1);
      final r = apply(before, RemoveFromQueue(e('zzz')));

      expect(r.changed, isFalse);
      expect(r.state, before);
    });
  });

  // -------------------------------------------------------------------------
  group('ReorderQueue', () {
    test('moves the item', () {
      final r = apply(queueOf('a b c d', position: 1),
          const ReorderQueue(from: 0, to: 3));

      expect(r.state.active!.items, eps('b c d a'));
      expectValid(r.state);
    });

    test('never changes what is playing', () {
      final before = queueOf('a b c d', position: 1);
      final r = apply(before, const ReorderQueue(from: 0, to: 3));

      expect(before.nowPlaying, e('b'));
      expect(r.state.nowPlaying, e('b'), reason: 'position follows the episode');
      expect(r.state.position, 0);
    });

    test('leaves detached playback alone', () {
      final r = apply(
        queueOf('a b c', source: const Detached(EpisodeId('z'))),
        const ReorderQueue(from: 2, to: 0),
      );

      expect(r.state.active!.items, eps('c a b'));
      expect(r.state.nowPlaying, e('z'));
      expectValid(r.state);
    });

    test('is a no-op with no active queue', () {
      final r = apply(QueueState.empty, const ReorderQueue(from: 0, to: 1));

      expect(r.changed, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('invariants', () {
    test('a cuesheet rejects a duplicated episode', () {
      expect(
        () => Cuesheet(
          id: const CuesheetId('x'),
          kind: CuesheetKind.ephemeral,
          items: eps('a b a'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a saved cuesheet requires a title', () {
      expect(
        () => Cuesheet(
          id: const CuesheetId('x'),
          kind: CuesheetKind.saved,
          items: eps('a'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a long sequence of intents never produces an invalid state', () {
      final ids = sequentialIds();
      var state = QueueState.empty;

      final script = <PlaybackIntent>[
        PlayFromHere(e('c'), TraversalOrder.ascending),
        AppendToQueue(e('a')),
        InsertNext(e('e')),
        PlayJustThis(e('zz')),
        RemoveFromQueue(e('c')),
        const ReorderQueue(from: 0, to: 2),
        ReplaceQueue(eps('p q r'), startAt: 1),
        RemoveFromQueue(e('q')),
        RemoveFromQueue(e('p')),
        RemoveFromQueue(e('r')),
      ];

      for (final intent in script) {
        state = applyIntent(state, intent, eps('a b c d e'),
                newCuesheetId: ids)
            .state;
        expectValid(state);
      }
    });
  });
}
