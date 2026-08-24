import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 8, 24, 12);
const hour = Duration(hours: 1);

EpisodeId e(String id) => EpisodeId(id);

Cuesheet sheet(List<String> ids) => Cuesheet(
      id: const CuesheetId('cs'),
      kind: CuesheetKind.ephemeral,
      items: [for (final id in ids) e(id)],
    );

QueueState queueOf(
  List<String> ids, {
  int position = 0,
  PlaybackSource? source = const FromQueue(),
}) =>
    QueueState(active: sheet(ids), position: position, source: source);

PlaybackTick tick(
  String episode, {
  required Duration position,
  PlaybackStatus status = PlaybackStatus.playing,
  Duration? duration,
}) =>
    PlaybackTick(
      episode: e(episode),
      position: position,
      status: status,
      duration: duration,
    );

PlaybackOutcome run(
  PlaybackTick t, {
  QueueState? queue,
  ListeningState? listening,
  Duration? episodeDuration = hour,
  DateTime? at,
  DateTime? lastWriteAt,
}) =>
    onTick(
      t,
      queue: queue ?? queueOf(['a', 'b', 'c']),
      listening: listening ?? ListeningState(episodeId: t.episode),
      episodeDuration: episodeDuration,
      now: at ?? now,
      lastWriteAt: lastWriteAt,
    );

void main() {
  group('an ordinary tick', () {
    test('moves the playhead and nothing else', () {
      final outcome = run(tick('a', position: const Duration(minutes: 5)));
      expect(outcome.listening.position, const Duration(minutes: 5));
      expect(outcome.queue, isNull);
      expect(outcome.command, const KeepGoing());
    });

    test('counts a start once the threshold is exceeded', () {
      final outcome = run(tick('a', position: const Duration(seconds: 61)));
      expect(outcome.listening.startCount, 1);
      expect(outcome.listening.firstPlayedAt, now);
    });

    test('does not count a start at exactly the threshold', () {
      // The guard against a stray tap moving an episode out of unplayed.
      final outcome = run(tick('a', position: const Duration(seconds: 60)));
      expect(outcome.listening.startCount, 0);
    });

    test('prefers the engine duration over the feed duration', () {
      // `<itunes:duration>` is typed by a person; this was measured off the
      // file. Here the feed is an hour out, and only the engine's number puts
      // the playhead inside the finish threshold.
      final outcome = run(
        tick('a', position: const Duration(minutes: 29, seconds: 45),
            duration: const Duration(minutes: 30)),
        episodeDuration: hour,
      );
      expect(outcome.listening.playCount, 1);
    });
  });

  group('persisting the playhead', () {
    test('writes immediately when nothing has been written yet', () {
      expect(run(tick('a', position: hour ~/ 2)).persist, isTrue);
    });

    test('holds off during steady playback', () {
      final outcome = run(
        tick('a', position: const Duration(minutes: 5)),
        lastWriteAt: now.subtract(const Duration(seconds: 3)),
      );
      expect(outcome.persist, isFalse);
    });

    test('writes once the interval has elapsed', () {
      final outcome = run(
        tick('a', position: const Duration(minutes: 5)),
        lastWriteAt: now.subtract(positionWriteInterval),
      );
      expect(outcome.persist, isTrue);
    });

    test('anything that is not playing forces a write', () {
      // §9: losing your place is the complaint, so every state change writes.
      for (final status in [
        PlaybackStatus.paused,
        PlaybackStatus.idle,
        PlaybackStatus.buffering,
        PlaybackStatus.loading,
      ]) {
        final outcome = run(
          tick('a', position: const Duration(minutes: 5), status: status),
          lastWriteAt: now,
        );
        expect(outcome.persist, isTrue, reason: '$status');
      }
    });
  });

  group('completing an episode from the queue', () {
    late PlaybackOutcome outcome;
    setUp(() => outcome = run(
          tick('a', position: hour, status: PlaybackStatus.completed),
          queue: queueOf(['a', 'b', 'c']),
        ));

    test('counts the play and stamps it finished', () {
      expect(outcome.listening.playCount, 1);
      expect(outcome.listening.finishedAt, now);
      expect(outcome.persist, isTrue);
    });

    test('advances the playhead and plays the next episode', () {
      expect(outcome.queue!.position, 1);
      expect(outcome.queue!.source, const FromQueue());
      expect(outcome.command, PlayNext(e('b')));
    });

    test('leaves the finished episode in the queue', () {
      // Rule 1: finishing is not an intent, so it does not get to mutate the
      // queue. The cuesheet is a document with a playhead.
      expect(outcome.queue!.active!.items, [e('a'), e('b'), e('c')]);
    });

    test('snaps the playhead to the end even from a short last tick', () {
      final short = run(
        tick('a', position: const Duration(minutes: 12),
            status: PlaybackStatus.completed),
      );
      expect(short.listening.position, hour);
    });

    test('an episode of unknown length still ends, but counts no play', () {
      // Nothing to measure against, so `finished` cannot be inferred. Rare,
      // and better than inventing a duration.
      final unknown = run(
        tick('a', position: const Duration(minutes: 12),
            status: PlaybackStatus.completed),
        episodeDuration: null,
      );
      expect(unknown.listening.position, const Duration(minutes: 12));
      expect(unknown.listening.playCount, 0);
      expect(unknown.command, PlayNext(e('b')));
    });
  });

  group('completing the last episode in the queue', () {
    late PlaybackOutcome outcome;
    setUp(() => outcome = run(
          tick('c', position: hour, status: PlaybackStatus.completed),
          queue: queueOf(['a', 'b', 'c'], position: 2),
        ));

    test('stops rather than wrapping', () {
      expect(outcome.command, const Halt());
      expect(outcome.queue!.source, isNull);
    });

    test('never produces a position past the last item', () {
      // `applyIntent` clamps to items.length - 1 everywhere. A position of 3
      // here would be silently corrected by the next intent, turning
      // "finished the queue" into "sitting on the last episode".
      expect(outcome.queue!.position, 2);
      expect(outcome.queue!.position,
          lessThan(outcome.queue!.active!.items.length));
    });

    test('still counts the play', () {
      expect(outcome.listening.playCount, 1);
    });
  });

  group('completing a detached episode', () {
    late PlaybackOutcome outcome;
    setUp(() => outcome = run(
          tick('z', position: hour, status: PlaybackStatus.completed),
          queue: queueOf(['a', 'b', 'c'],
              position: 1, source: Detached(e('z'))),
        ));

    test('stops instead of handing playback to the queue', () {
      // §5.3. A one-off tap must never end up starting audio nobody asked for.
      expect(outcome.command, const Halt());
      expect(outcome.queue!.source, isNull);
    });

    test('leaves the queue exactly where it was', () {
      expect(outcome.queue!.position, 1);
      expect(outcome.queue!.active!.items, [e('a'), e('b'), e('c')]);
    });

    test('still records the listen', () {
      expect(outcome.listening.playCount, 1);
      expect(outcome.persist, isTrue);
    });
  });

  group('stale ticks', () {
    test('a completion for something that is not playing leaves the queue', () {
      // A late report from an episode we already moved off. Its listening
      // state is still worth keeping; the queue is not its business.
      final outcome = run(
        tick('a', position: hour, status: PlaybackStatus.completed),
        queue: queueOf(['a', 'b', 'c'], position: 1),
      );
      expect(outcome.queue, isNull);
      expect(outcome.command, const KeepGoing());
      expect(outcome.listening.playCount, 1);
    });

    test('a completion with nothing playing at all just halts', () {
      final outcome = run(
        tick('a', position: hour, status: PlaybackStatus.completed),
        queue: const QueueState(),
      );
      expect(outcome.command, const Halt());
      expect(outcome.queue, isNull);
    });
  });

  test('replaying an episode in the same session counts one play', () {
    // Scrub back five minutes near the end and let it finish again.
    var state = ListeningState(episodeId: e('a'));
    state = run(tick('a', position: hour, status: PlaybackStatus.completed),
            listening: state)
        .listening;
    expect(state.playCount, 1);

    state = run(tick('a', position: const Duration(minutes: 55)),
            listening: state)
        .listening;
    state = run(tick('a', position: hour, status: PlaybackStatus.completed),
            listening: state)
        .listening;
    expect(state.playCount, 1, reason: 'one listen, not two');
  });

  test('starting the episode over counts a second play', () {
    var state = ListeningState(episodeId: e('a'));
    state = run(tick('a', position: hour, status: PlaybackStatus.completed),
            listening: state)
        .listening;
    // Back to the top: the session ends and the next finish is a new listen.
    state = run(tick('a', position: Duration.zero), listening: state).listening;
    state = run(tick('a', position: hour, status: PlaybackStatus.completed),
            listening: state)
        .listening;
    expect(state.playCount, 2);
    expect(state.startCount, 2);
  });
}
