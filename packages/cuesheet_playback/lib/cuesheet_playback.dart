/// Audio for Cuesheet.
///
/// Implements the `AudioEngine` interface declared by `cuesheet_domain`, and
/// nothing else. This is the least unit-testable layer in the project, which
/// is exactly why it is the thinnest and sits behind an interface (§11).
library;

export 'src/background.dart';
export 'src/fake_audio_engine.dart';
export 'src/just_audio_engine.dart';
