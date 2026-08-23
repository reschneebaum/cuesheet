import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:test/test.dart';

const ep = EpisodeId('ep');
const hour = Duration(minutes: 60);
final t0 = DateTime.utc(2026, 1, 1, 12);

ListeningState blank() => const ListeningState(episodeId: ep);

Duration secs(int n) => Duration(seconds: n);

void main() {
  group('isFinished', () {
    test('is false well short of the end', () {
      final s = blank().copyWith(position: const Duration(minutes: 30));
      expect(isFinished(s, episodeDuration: hour), isFalse);
    });

    test('is true inside the finish threshold', () {
      final s = blank().copyWith(position: const Duration(minutes: 59, seconds: 30));
      expect(isFinished(s, episodeDuration: hour), isTrue);
    });

    test('is false one second outside the finish threshold', () {
      final s = blank().copyWith(position: const Duration(minutes: 59, seconds: 29));
      expect(isFinished(s, episodeDuration: hour), isFalse);
    });

    test('is true when marked explicitly, wherever the position is', () {
      final s = blank().copyWith(explicitlyFinished: true);
      expect(isFinished(s, episodeDuration: hour), isTrue);
    });

    test('is never true by position when the duration is unknown', () {
      final s = blank().copyWith(position: const Duration(hours: 99));
      expect(isFinished(s, episodeDuration: null), isFalse);
    });

    test('requires the whole thing for an episode shorter than the threshold', () {
      // A 20s episode with a 30s finish threshold must not be born finished.
      expect(isFinished(blank(), episodeDuration: secs(20)), isFalse);
      final s = blank().copyWith(position: secs(20));
      expect(isFinished(s, episodeDuration: secs(20)), isTrue);
    });
  });

  group('listenStateOf', () {
    ListenState stateAt(Duration position, {DateTime? now, DateTime? lastPlayed}) =>
        listenStateOf(
          blank().copyWith(position: position, lastPlayedAt: lastPlayed),
          episodeDuration: hour,
          now: now ?? t0,
        );

    test('is unplayed at the very beginning', () {
      expect(stateAt(Duration.zero), ListenState.unplayed);
    });

    test('is still unplayed at exactly the start threshold', () {
      // The threshold must be *exceeded*: this is the stray-tap guard.
      expect(stateAt(secs(60)), ListenState.unplayed);
    });

    test('is started once past the start threshold', () {
      expect(stateAt(secs(61)), ListenState.started);
    });

    test('is finished near the end', () {
      expect(stateAt(const Duration(minutes: 59, seconds: 45)),
          ListenState.finished);
    });

    test('becomes a relisten candidate once the finish goes stale', () {
      final finished = const Duration(minutes: 59, seconds: 45);
      final longAgo = t0.subtract(const Duration(days: 91));
      expect(stateAt(finished, lastPlayed: longAgo),
          ListenState.relistenCandidate);
    });

    test('is merely finished while the finish is recent', () {
      final finished = const Duration(minutes: 59, seconds: 45);
      final recently = t0.subtract(const Duration(days: 89));
      expect(stateAt(finished, lastPlayed: recently), ListenState.finished);
    });

    test('is not a relisten candidate with no play history at all', () {
      final s = blank().copyWith(explicitlyFinished: true);
      expect(listenStateOf(s, episodeDuration: hour, now: t0),
          ListenState.finished);
    });

    test('an episode being relistened to right now is started, not a candidate', () {
      final longAgo = t0.subtract(const Duration(days: 200));
      final s = blank().copyWith(
        position: const Duration(minutes: 5),
        playCount: 1,
        lastPlayedAt: longAgo,
      );
      expect(listenStateOf(s, episodeDuration: hour, now: t0),
          ListenState.started);
    });
  });

  group('advance', () {
    test('records the position and when it happened', () {
      final s = advance(blank(), to: const Duration(minutes: 5),
          episodeDuration: hour, now: t0);

      expect(s.position, const Duration(minutes: 5));
      expect(s.lastPlayedAt, t0);
    });

    test('counts a start when the threshold is first crossed', () {
      final s = advance(blank(), to: secs(61), episodeDuration: hour, now: t0);

      expect(s.startCount, 1);
      expect(s.firstPlayedAt, t0);
    });

    test('does not count a second start while still in the same session', () {
      var s = advance(blank(), to: secs(61), episodeDuration: hour, now: t0);
      s = advance(s, to: secs(120), episodeDuration: hour, now: t0);

      expect(s.startCount, 1);
    });

    test('does not count a start for a stray tap below the threshold', () {
      final s = advance(blank(), to: secs(3), episodeDuration: hour, now: t0);

      expect(s.startCount, 0);
      expect(s.firstPlayedAt, isNull);
      expect(listenStateOf(s, episodeDuration: hour, now: t0),
          ListenState.unplayed);
    });

    test('counts a play on reaching the end, and records when', () {
      var s = advance(blank(), to: const Duration(minutes: 30),
          episodeDuration: hour, now: t0);
      s = advance(s, to: const Duration(minutes: 59, seconds: 40),
          episodeDuration: hour, now: t0);

      expect(s.playCount, 1);
      expect(s.finishedAt, t0);
    });

    test('does not count again while playing out the last few seconds', () {
      var s = advance(blank(), to: const Duration(minutes: 59, seconds: 40),
          episodeDuration: hour, now: t0);
      s = advance(s, to: const Duration(minutes: 59, seconds: 55),
          episodeDuration: hour, now: t0);

      expect(s.playCount, 1);
    });

    test('scrubbing back mid-session and re-finishing counts only once', () {
      var s = advance(blank(), to: const Duration(minutes: 59, seconds: 40),
          episodeDuration: hour, now: t0);
      s = advance(s, to: const Duration(minutes: 50), episodeDuration: hour, now: t0);
      s = advance(s, to: const Duration(minutes: 59, seconds: 40),
          episodeDuration: hour, now: t0);

      expect(s.playCount, 1, reason: 'still the same listen session');
    });

    test('starting over from the top counts a second play', () {
      var s = advance(blank(), to: const Duration(minutes: 59, seconds: 40),
          episodeDuration: hour, now: t0);
      s = advance(s, to: Duration.zero, episodeDuration: hour, now: t0);
      s = advance(s, to: const Duration(minutes: 59, seconds: 40),
          episodeDuration: hour, now: t0);

      expect(s.playCount, 2);
      expect(s.startCount, 2);
    });

    test('going back to the top clears an explicit finish', () {
      var s = markFinished(blank(), now: t0, episodeDuration: hour);
      s = advance(s, to: Duration.zero, episodeDuration: hour, now: t0);

      expect(s.explicitlyFinished, isFalse);
      expect(isFinished(s, episodeDuration: hour), isFalse);
    });

    test('never auto-finishes when the duration is unknown', () {
      final s = advance(blank(), to: const Duration(hours: 99),
          episodeDuration: null, now: t0);

      expect(s.playCount, 0);
      expect(isFinished(s, episodeDuration: null), isFalse);
    });
  });

  group('markFinished / markUnplayed', () {
    test('marking finished counts a play and jumps to the end', () {
      final s = markFinished(blank(), now: t0, episodeDuration: hour);

      expect(s.explicitlyFinished, isTrue);
      expect(s.playCount, 1);
      expect(s.position, hour);
      expect(s.finishedAt, t0);
    });

    test('marking finished twice in a session counts one play', () {
      var s = markFinished(blank(), now: t0, episodeDuration: hour);
      s = markFinished(s, now: t0, episodeDuration: hour);

      expect(s.playCount, 1);
    });

    test('marking finished after listening to the end does not double count', () {
      var s = advance(blank(), to: const Duration(minutes: 59, seconds: 40),
          episodeDuration: hour, now: t0);
      s = markFinished(s, now: t0, episodeDuration: hour);

      expect(s.playCount, 1);
    });

    test('marking unplayed resets progress but keeps the history', () {
      var s = advance(blank(), to: const Duration(minutes: 59, seconds: 40),
          episodeDuration: hour, now: t0);
      s = markUnplayed(s);

      expect(s.position, Duration.zero);
      expect(s.explicitlyFinished, isFalse);
      expect(s.finishedAt, isNull);
      expect(s.playCount, 1, reason: 'you did listen to it');
      expect(s.lastPlayedAt, t0);
      expect(listenStateOf(s, episodeDuration: hour, now: t0),
          ListenState.unplayed);
    });
  });

  group('remaining', () {
    test('is null when the duration is unknown', () {
      expect(remaining(blank(), episodeDuration: null), isNull);
    });

    test('is what is left', () {
      final s = blank().copyWith(position: const Duration(minutes: 20));
      expect(remaining(s, episodeDuration: hour), const Duration(minutes: 40));
    });

    test('never goes negative', () {
      final s = blank().copyWith(position: const Duration(minutes: 70));
      expect(remaining(s, episodeDuration: hour), Duration.zero);
    });
  });
}
