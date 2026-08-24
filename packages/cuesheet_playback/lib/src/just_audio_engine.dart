import 'dart:async';

import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:just_audio/just_audio.dart' as ja;

/// [AudioEngine] over `just_audio`.
///
/// The whole adapter, and deliberately dull. Every decision about what to play
/// and what a position means lives in `onTick`; this translates four streams
/// into one and six methods into six.
class JustAudioEngine implements AudioEngine {
  JustAudioEngine({ja.AudioPlayer? player})
      : _player = player ?? ja.AudioPlayer() {
    _wire();
  }

  final ja.AudioPlayer _player;
  final _ticks = StreamController<PlaybackTick>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];

  EpisodeAudio? _loaded;
  Duration _position = Duration.zero;
  Duration? _duration;
  ja.PlayerState _state = ja.PlayerState(false, ja.ProcessingState.idle);
  double _speed = 1;

  @override
  Stream<PlaybackTick> get ticks => _ticks.stream;

  /// `just_audio` reports position, duration, player state and speed on four
  /// separate streams. They are merged by keeping the latest of each and
  /// emitting on any change, rather than by pulling in `rxdart` for a
  /// `combineLatest` — one dependency and one class is not worth it for four
  /// fields.
  void _wire() {
    _subscriptions.addAll([
      _player.positionStream.listen((p) {
        _position = p;
        _emit();
      }),
      _player.durationStream.listen((d) {
        _duration = d;
        _emit();
      }),
      _player.playerStateStream.listen((s) {
        _state = s;
        _emit();
      }),
      _player.speedStream.listen((s) {
        _speed = s;
        _emit();
      }),
    ]);
  }

  void _emit() {
    final loaded = _loaded;
    if (loaded == null || _ticks.isClosed) return;
    _ticks.add(PlaybackTick(
      episode: loaded.id,
      position: _position,
      status: _statusOf(_state),
      // The engine measured the file; prefer it, but fall back to the feed's
      // claim while the header is still being read.
      duration: _duration ?? loaded.duration,
      speed: _speed,
    ));
  }

  static PlaybackStatus _statusOf(ja.PlayerState state) =>
      switch (state.processingState) {
        ja.ProcessingState.idle => PlaybackStatus.idle,
        ja.ProcessingState.loading => PlaybackStatus.loading,
        ja.ProcessingState.buffering => PlaybackStatus.buffering,
        ja.ProcessingState.ready =>
          state.playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        ja.ProcessingState.completed => PlaybackStatus.completed,
      };

  @override
  Future<void> load(EpisodeAudio audio, {Duration startAt = Duration.zero}) async {
    _loaded = audio;
    // Reset rather than carry the previous episode's numbers into the first
    // tick of this one: a stale duration here would be read as the new
    // episode's length and could finish it on arrival.
    _position = startAt;
    _duration = audio.duration;

    await _player.setAudioSource(
      ja.AudioSource.uri(audio.url),
      initialPosition: startAt,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration to) => _player.seek(to);

  @override
  Future<void> setSpeed(double rate) => _player.setSpeed(rate);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _ticks.close();
    await _player.dispose();
  }
}
