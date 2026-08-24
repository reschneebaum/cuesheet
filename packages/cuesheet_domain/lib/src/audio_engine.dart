import 'package:freezed_annotation/freezed_annotation.dart';

import 'ids.dart';

part 'audio_engine.freezed.dart';

/// What the engine is doing right now.
///
/// [completed] is the one that carries a decision: it is the engine saying the
/// audio ran to its end, which is stronger evidence of "finished" than any
/// position threshold, and is what drives the queue forward (§5.3).
enum PlaybackStatus { idle, loading, buffering, playing, paused, completed }

/// One report from the engine.
@freezed
abstract class PlaybackTick with _$PlaybackTick {
  const factory PlaybackTick({
    required EpisodeId episode,
    required Duration position,
    required PlaybackStatus status,

    /// The engine's own idea of how long the audio is, which is frequently
    /// better than the feed's: `<itunes:duration>` is hand-entered often
    /// enough to be wrong, while this was measured off the file.
    Duration? duration,
    @Default(1.0) double speed,
  }) = _PlaybackTick;
}

/// Everything the engine needs to play one episode.
///
/// Carries display metadata as well as the URL because the lock screen needs
/// it: `just_audio_background` builds its now-playing item from what it is
/// handed at load time, and going back to the database from inside the audio
/// layer would point a dependency arrow the wrong way (§3).
@freezed
abstract class EpisodeAudio with _$EpisodeAudio {
  const factory EpisodeAudio({
    required EpisodeId id,
    required Uri url,
    required String title,
    String? podcastTitle,
    Uri? artworkUrl,
    Duration? duration,
  }) = _EpisodeAudio;
}

/// The audio boundary, declared here and implemented in `cuesheet_playback`.
///
/// Deliberately the smallest surface that can serve §5 and §9. It knows
/// nothing about queues, cuesheets, listening history or thresholds — it plays
/// one thing at a time and says what it is doing. Everything that decides
/// *what* to play is a pure function over its ticks, which is what keeps the
/// least testable layer in the project also the thinnest.
abstract interface class AudioEngine {
  /// Position, duration, buffering and state. Broadcast: the coordinator and
  /// the UI both listen, and a single-subscription stream would let whichever
  /// got there first starve the other.
  Stream<PlaybackTick> get ticks;

  Future<void> load(EpisodeAudio audio, {Duration startAt});

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration to);

  Future<void> setSpeed(double rate);

  Future<void> stop();

  Future<void> dispose();
}
