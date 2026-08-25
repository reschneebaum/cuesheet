import 'dart:async';

import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// The imperative shell around [onTick].
///
/// Holds no rules. Every decision — whether to write the playhead, whether the
/// queue advances, what plays next — comes back from the pure function; this
/// subscribes, reads, writes, and drives the engine. If a behaviour needs
/// changing, it changes in `playback.dart` and this file does not move.
class PlaybackController {
  /// Dependencies are passed in rather than read from a [Ref], so the
  /// controller knows nothing about Riverpod and can be driven directly by a
  /// test. It also has to be this way: `dispose` runs while the provider is
  /// being torn down, and a `Ref` is already invalid by then.
  PlaybackController({
    required AudioEngine engine,
    required EpisodeRepository episodes,
    required ListeningRepository listening,
    required CuesheetRepository cuesheets,
    required DateTime Function() clock,
    this.onError,
  })  : _engine = engine,
        _episodes = episodes,
        _listeningRepository = listening,
        _cuesheets = cuesheets,
        _clock = clock {
    _tickSubscription = _engine.ticks.listen(
      (tick) => _serially(() => _handleTick(tick)),
    );
    _queueSubscription = _cuesheets
        .watchQueue()
        .listen((queue) => _serially(() => _handleQueue(queue)));
  }

  final AudioEngine _engine;
  final EpisodeRepository _episodes;
  final ListeningRepository _listeningRepository;
  final CuesheetRepository _cuesheets;
  final DateTime Function() _clock;

  /// Where a failed tick goes. Swallowing it would leave playback silently
  /// stuck; throwing would poison the serialization chain and stop every later
  /// tick with it.
  final void Function(String message)? onError;

  late final StreamSubscription<PlaybackTick> _tickSubscription;
  late final StreamSubscription<QueueState> _queueSubscription;

  QueueState _queue = QueueState.empty;

  /// The loaded episode's listening state, held in memory between writes.
  ///
  /// Re-reading it per tick would be a database round trip five times a second
  /// for a value we already know. Re-read on every load, so an edit made while
  /// nothing is playing is picked up.
  ListeningState? _listening;
  EpisodeId? _loaded;
  Duration? _loadedDuration;
  DateTime? _lastWriteAt;
  PlaybackStatus _status = PlaybackStatus.idle;

  /// Whether a queue emission has been seen yet.
  ///
  /// The first one is the queue restored from disk at launch, and must not
  /// start audio: the app opening and immediately playing is the surprise this
  /// whole project is a reaction to. Every later change to what is playing came
  /// from an intent that meant it — `applyIntent` only ever sets a source for
  /// `PlayFromHere`, `ReplaceQueue` and `PlayJustThis` — so those do play.
  bool _restored = false;

  DateTime get _now => _clock();

  PlaybackStatus get status => _status;

  Future<void> togglePlayPause() async {
    if (_status == PlaybackStatus.playing) {
      await _engine.pause();
      return;
    }
    if (_loaded == null) {
      final target = _queue.nowPlaying;
      if (target == null) return;
      await _load(target, play: true);
      return;
    }
    await _engine.play();
  }

  Future<void> seekBy(Duration delta) =>
      seekTo((_listening?.position ?? Duration.zero) + delta);

  Future<void> seekTo(Duration at) async {
    await _engine.seek(at < Duration.zero ? Duration.zero : at);
    // §9 forces a write on seek, and this is the only place that can do it:
    // the resulting tick still reports `playing`, so `onTick` cannot tell the
    // jump from ordinary progress and leaves it to the debounce. Queued behind
    // the pending tick so it writes the position the seek produced, not the
    // one before it.
    await _serially(flush);
  }

  Future<void> setSpeed(double rate) => _engine.setSpeed(rate);

  /// Write the playhead now.
  ///
  /// §9 forces a write on events a tick cannot report — a queue mutation, an
  /// app going to the background. Pause and seek force one too, but those the
  /// engine does report, so `onTick` already covers them.
  Future<void> flush() async {
    final listening = _listening;
    if (listening == null) return;
    await _listeningRepository.save(listening);
    _lastWriteAt = _now;
  }

  /// Stops listening, and deliberately writes nothing.
  ///
  /// §9 is explicit that nothing relies on a clean termination — the playhead
  /// is written on a debounce and forced on pause, seek, queue mutation,
  /// interruption and backgrounding, all of which happen before teardown. A
  /// write here would be the one that *did* rely on it, and it is also a
  /// database round trip during provider disposal, which leaves a timer
  /// pending after the tree is gone (see `docs/notes/widget-test-traps.md`).
  ///
  /// Does not dispose the engine either. Whoever built it owns it — the
  /// provider in production, the test that overrode it otherwise — and
  /// disposing from two places is a double `close()` on its stream.
  /// Synchronous, and that matters. `ref.onDispose` does not await what it is
  /// given, so an `async` version would not even *start* cancelling until a
  /// microtask later — by which point a test has finished pumping, drift's
  /// query stream is still registered as open, and closing the database waits
  /// for it forever. Calling `cancel()` without awaiting starts the
  /// cancellation now and lets the zero-duration timer drift schedules fire on
  /// the next pump.
  void dispose() {
    unawaited(_tickSubscription.cancel());
    unawaited(_queueSubscription.cancel());
  }

  Future<void> _handleQueue(QueueState queue) async {
    _queue = queue;
    final target = queue.nowPlaying;

    // Marked on the first emission whatever it contains, including the very
    // common empty one. Deferring it until something is actually playing would
    // make the *next* change look like the restore, and the first intent of
    // the session would silently load without playing.
    final wasRestored = _restored;
    _restored = true;

    if (target == _loaded) return;

    if (target == null) {
      await _engine.stop();
      _loaded = null;
      _listening = null;
      return;
    }

    await _load(target, play: wasRestored);
  }

  Future<void> _load(EpisodeId id, {required bool play}) async {
    final view = await _episodes.byId(id);
    if (view == null) return;

    final listening = await _listeningRepository.byEpisode(id);
    final duration = view.episode.duration;

    // Start a finished episode over rather than resuming at its end. Resuming
    // would put the playhead inside the finish threshold, the engine would
    // report completion immediately, and a queue of already-heard episodes
    // would advance through itself as fast as it could load them.
    final finished = isFinished(listening, episodeDuration: duration);
    final startAt = finished ? Duration.zero : listening.position;

    _loaded = id;
    _loadedDuration = duration;
    _listening = listening;
    _lastWriteAt = null;

    await _engine.load(
      EpisodeAudio(
        id: id,
        url: view.episode.enclosureUrl,
        title: view.episode.title,
        podcastTitle: view.podcastTitle,
        artworkUrl: view.episode.artworkUrl,
        duration: duration,
      ),
      startAt: startAt,
    );
    if (play) await _engine.play();
  }

  Future<void> _handleTick(PlaybackTick tick) async {
    _status = tick.status;

    final listening = _listening;
    // A tick for something we are not tracking — a late report from an episode
    // already unloaded. Nothing useful to fold it into.
    if (listening == null || tick.episode != listening.episodeId) return;

    final outcome = onTick(
      tick,
      queue: _queue,
      listening: listening,
      episodeDuration: _loadedDuration,
      now: _now,
      lastWriteAt: _lastWriteAt,
    );

    _listening = outcome.listening;
    if (outcome.persist) {
      await _listeningRepository.save(outcome.listening);
      _lastWriteAt = _now;
    }

    // Saved without an undo snapshot, deliberately. Reaching the end of an
    // episode is not an intent, and an undo stack that fills up with "the
    // playhead moved on its own" would bury the entries the user can actually
    // reason about (§5.4).
    final next = outcome.queue;
    if (next != null) {
      _queue = next;
      await _cuesheets.saveQueue(next);
    }

    switch (outcome.command) {
      case KeepGoing():
        break;
      case Halt():
        await _engine.stop();
        _loaded = null;
      case PlayNext(:final episode):
        await _load(episode, play: true);
    }
  }

  /// Dart has no locks and no actors, and tick handlers are async — two ticks
  /// arriving close together would otherwise interleave their reads and writes
  /// and race each other to `saveQueue`. Chaining onto a single future
  /// serializes them, which is the ordinary Dart answer to a problem Swift
  /// would solve with an actor.
  Future<void> _chain = Future<void>.value();

  Future<void> _serially(Future<void> Function() work) {
    _chain = _chain.then((_) => work()).catchError((Object error) {
      // A failed tick must not poison the chain and stop every later one.
      onError?.call('playback error: $error');
    });
    return _chain;
  }
}

/// Created once and kept for the life of the app.
///
/// `Provider` rather than anything lazier on purpose: the controller has to be
/// listening to ticks before the first one arrives, and a provider that is only
/// built when something reads it would miss them.
final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final controller = PlaybackController(
    engine: ref.watch(audioEngineProvider),
    episodes: ref.watch(episodeRepositoryProvider),
    listening: ref.watch(listeningRepositoryProvider),
    cuesheets: ref.watch(cuesheetRepositoryProvider),
    clock: ref.watch(clockProvider),
    onError: (message) =>
        ref.read(ingestionLogProvider.notifier).add(message),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
