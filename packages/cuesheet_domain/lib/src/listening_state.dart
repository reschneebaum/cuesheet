import 'package:freezed_annotation/freezed_annotation.dart';

import 'ids.dart';

part 'listening_state.freezed.dart';

/// How much of an episode has been listened to, and how often.
///
/// Keyed by [EpisodeId] and stored separately from [Episode] so feed churn
/// cannot destroy it.
@freezed
abstract class ListeningState with _$ListeningState {
  const factory ListeningState({
    required EpisodeId episodeId,
    @Default(Duration.zero) Duration position,

    /// Times this episode has been listened to completion.
    @Default(0) int playCount,

    /// Times a listen session has begun — i.e. the start threshold has been
    /// crossed from below.
    @Default(0) int startCount,
    DateTime? firstPlayedAt,
    DateTime? lastPlayedAt,
    DateTime? finishedAt,

    /// Marked finished by the user rather than by reaching the end.
    @Default(false) bool explicitlyFinished,

    /// Whether the current listen session has already been counted toward
    /// [playCount]. Scrubbing backwards within a session must not let the
    /// same listen count twice; dropping below the start threshold ends the
    /// session and clears this.
    @Default(false) bool countedThisSession,
  }) = _ListeningState;
}

/// The boundaries that decide what "started", "finished", and "worth a
/// relisten" mean. Configurable because the defaults are guesses.
@freezed
abstract class ListeningThresholds with _$ListeningThresholds {
  const factory ListeningThresholds({
    /// An episode is not "started" until this far in, so a stray tap cannot
    /// move something out of unplayed. This exists because of a specific
    /// complaint about other apps.
    @Default(Duration(seconds: 60)) Duration startAfter,

    /// Within this distance of the end counts as finished — podcasts trail off
    /// into credits and nobody listens to the last twenty seconds.
    @Default(Duration(seconds: 30)) Duration finishWithin,

    /// How stale a finished episode must be before it is offered as a
    /// relisten candidate.
    @Default(Duration(days: 90)) Duration relistenAfter,
  }) = _ListeningThresholds;

  static const ListeningThresholds standard = ListeningThresholds();
}
