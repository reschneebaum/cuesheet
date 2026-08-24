import 'package:cuesheet_playback/cuesheet_playback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/debug_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before `runApp`, and so before anything can build an engine: background
  // audio works by intercepting audio source construction, and a player made
  // first is invisible to the lock screen for the rest of its life.
  //
  // Caught rather than allowed to propagate. This is the one call in the app
  // that can fail for reasons that have nothing to do with the app — an OS
  // refusing an audio session, a platform with no implementation — and losing
  // the lock screen is a bad afternoon, while a launch that dies before the
  // first frame is a black window with no way to find out why.
  try {
    await initializeBackgroundAudio();
  } on Object catch (error, stack) {
    debugPrint('lock-screen controls unavailable: $error\n$stack');
  }

  runApp(const ProviderScope(child: DebugApp()));
}
