import 'package:just_audio_background/just_audio_background.dart';

/// Turn on lock-screen controls and background playback.
///
/// Must be called before any [AudioEngine] is built: `just_audio_background`
/// works by intercepting audio source construction, and a player created
/// before it is initialised is invisible to the lock screen for its whole life.
///
/// Not a plugin itself, despite appearances — it is pure Dart over
/// `audio_service`, which is the plugin, and which supports macOS as well as
/// iOS. That is why this is called unconditionally rather than guarded by
/// platform: the debug harness gets the same now-playing surface as the phone,
/// which is the difference between verifying this on a device and verifying it
/// in the loop you already have open.
///
/// The Android arguments are required by the API and inert here — §2 puts
/// Android out of scope for v1 — but naming the channel now costs nothing and
/// avoids a mystery when it is not.
Future<void> initializeBackgroundAudio() => JustAudioBackground.init(
      androidNotificationChannelId: 'com.heliumfoot.cuesheet.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
    );
