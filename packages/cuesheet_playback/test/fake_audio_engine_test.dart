import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_playback/cuesheet_playback.dart';
import 'package:flutter_test/flutter_test.dart';

final audio = EpisodeAudio(
  id: const EpisodeId('e1'),
  url: Uri.parse('https://cdn.example.com/1.mp3'),
  title: 'The Mercator Problem',
  duration: const Duration(minutes: 30),
);

void main() {
  late FakeAudioEngine engine;
  late List<PlaybackTick> seen;

  setUp(() {
    engine = FakeAudioEngine();
    seen = [];
    engine.ticks.listen(seen.add);
  });

  tearDown(() => engine.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('emits nothing until something is loaded', () async {
    engine.elapse(const Duration(seconds: 5));
    await settle();
    expect(seen, isEmpty);
  });

  test('loading reports the start position, paused', () async {
    await engine.load(audio, startAt: const Duration(minutes: 4));
    await settle();

    expect(seen.single.episode, const EpisodeId('e1'));
    expect(seen.single.position, const Duration(minutes: 4));
    expect(seen.single.status, PlaybackStatus.paused);
    expect(seen.single.duration, const Duration(minutes: 30));
  });

  test('a paused engine does not advance', () async {
    await engine.load(audio);
    engine.elapse(const Duration(minutes: 5));
    await settle();

    expect(engine.position, Duration.zero);
    expect(seen, hasLength(1), reason: 'only the load tick');
  });

  test('elapsing while playing moves the playhead one tick at a time',
      () async {
    await engine.load(audio);
    await engine.play();
    engine.elapse(const Duration(seconds: 30));
    engine.elapse(const Duration(seconds: 30));
    await settle();

    expect(engine.position, const Duration(minutes: 1));
    expect(seen.last.status, PlaybackStatus.playing);
    expect(seen.map((t) => t.position).toList(), [
      Duration.zero,
      Duration.zero,
      const Duration(seconds: 30),
      const Duration(minutes: 1),
    ]);
  });

  test('finishing snaps to the duration and reports completed', () async {
    await engine.load(audio);
    await engine.play();
    engine.elapse(const Duration(minutes: 2));
    engine.finish();
    await settle();

    expect(seen.last.status, PlaybackStatus.completed);
    expect(seen.last.position, const Duration(minutes: 30));
  });

  test('an interruption is indistinguishable from a pause, on purpose',
      () async {
    // A phone call and a tap on pause mean the same thing to the coordinator,
    // and it must not need to tell them apart.
    await engine.load(audio);
    await engine.play();
    engine.interrupt();
    await settle();

    expect(seen.last.status, PlaybackStatus.paused);
  });

  test('seeking moves the playhead without changing what is playing',
      () async {
    await engine.load(audio);
    await engine.play();
    await engine.seek(const Duration(minutes: 20));
    await settle();

    expect(seen.last.position, const Duration(minutes: 20));
    expect(seen.last.status, PlaybackStatus.playing);
  });

  test('records every call, in order', () async {
    await engine.load(audio, startAt: const Duration(minutes: 1));
    await engine.play();
    await engine.setSpeed(1.5);
    await engine.pause();
    await engine.stop();

    expect(engine.calls, [
      'load(e1, at: 0:01:00.000000)',
      'play',
      'setSpeed(1.5)',
      'pause',
      'stop',
    ]);
  });

  test('ticks are broadcast, so the coordinator and the UI can both listen',
      () async {
    // A single-subscription stream would let whichever listener got there
    // first starve the other.
    final second = <PlaybackTick>[];
    engine.ticks.listen(second.add);

    await engine.load(audio);
    await settle();

    expect(seen, hasLength(1));
    expect(second, hasLength(1));
  });

  test('the fake and onTick compose', () async {
    // The two halves of Phase 4 meeting: engine reports, pure function decides.
    await engine.load(audio);
    await engine.play();
    engine.finish();
    await settle();

    final outcome = onTick(
      seen.last,
      queue: QueueState(
        active: Cuesheet(
          id: const CuesheetId('cs'),
          kind: CuesheetKind.ephemeral,
          items: const [EpisodeId('e1'), EpisodeId('e2')],
        ),
        source: const FromQueue(),
      ),
      listening: const ListeningState(episodeId: EpisodeId('e1')),
      episodeDuration: const Duration(minutes: 30),
      now: DateTime.utc(2026, 8, 24),
    );

    expect(outcome.command, const PlayNext(EpisodeId('e2')));
    expect(outcome.listening.playCount, 1);
    expect(outcome.persist, isTrue);
  });
}
