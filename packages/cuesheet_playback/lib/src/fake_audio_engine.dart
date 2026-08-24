import 'dart:async';

import 'package:cuesheet_domain/cuesheet_domain.dart';

/// An [AudioEngine] with a hand-cranked clock.
///
/// §13: this layer's real verification is manual and on a device, so what the
/// rest of the project tests against is this. Time does not pass here — a test
/// calls [elapse] and gets exactly the ticks it asked for, which makes the
/// five-second write debounce and the finish thresholds assertable without
/// waiting five seconds or playing an hour of audio.
class FakeAudioEngine implements AudioEngine {
  final _controller = StreamController<PlaybackTick>.broadcast();

  EpisodeAudio? _loaded;
  Duration _position = Duration.zero;
  PlaybackStatus _status = PlaybackStatus.idle;
  double _speed = 1;

  /// Every call made, in order, so a test can assert that pausing wrote the
  /// playhead *and* that nothing loaded a second time.
  final List<String> calls = [];

  EpisodeAudio? get loaded => _loaded;
  Duration get position => _position;
  PlaybackStatus get status => _status;

  @override
  Stream<PlaybackTick> get ticks => _controller.stream;

  @override
  Future<void> load(EpisodeAudio audio, {Duration startAt = Duration.zero}) async {
    calls.add('load(${audio.id.value}, at: $startAt)');
    _loaded = audio;
    _position = startAt;
    _status = PlaybackStatus.paused;
    _emit();
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _status = PlaybackStatus.playing;
    _emit();
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _status = PlaybackStatus.paused;
    _emit();
  }

  @override
  Future<void> seek(Duration to) async {
    calls.add('seek($to)');
    _position = to;
    _emit();
  }

  @override
  Future<void> setSpeed(double rate) async {
    calls.add('setSpeed($rate)');
    _speed = rate;
    _emit();
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _status = PlaybackStatus.idle;
    _emit();
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _controller.close();
  }

  /// Move the playhead forward as if [by] of audio had played, emitting one
  /// tick. Does nothing unless something is playing, which is the point: a
  /// paused engine does not advance.
  void elapse(Duration by) {
    if (_status != PlaybackStatus.playing) return;
    _position += by;
    _emit();
  }

  /// Run out of audio: what the engine reports at the end of a file.
  void finish() {
    _position = _loaded?.duration ?? _position;
    _status = PlaybackStatus.completed;
    _emit();
  }

  /// A phone call, or headphones unplugged. Reports paused, like the real
  /// engine does — the coordinator must not need to tell the two apart.
  void interrupt() {
    _status = PlaybackStatus.paused;
    _emit();
  }

  /// Emit an arbitrary tick, for the cases the helpers above do not cover —
  /// buffering, or a stale report for an episode that is no longer loaded.
  void emit(PlaybackTick tick) => _controller.add(tick);

  void _emit() {
    final loaded = _loaded;
    if (loaded == null) return;
    _controller.add(PlaybackTick(
      episode: loaded.id,
      position: _position,
      status: _status,
      duration: loaded.duration,
      speed: _speed,
    ));
  }
}
