
import 'package:flutter/widgets.dart';

/// The type scale.
///
/// Two families and one deliberate rule about which is which. [display] is
/// Newsreader, and is spent only on the things a person came to read: a screen
/// title, an episode title on the now-playing screen. Everything else —
/// controls, metadata, list rows, counts — is the platform face, because a
/// control that announces itself in a serif is a control announcing the wrong
/// thing.
///
/// The platform face is requested as `null`, not by name. Naming
/// `.SF Pro Text` would pin the app to one OS and silently fall back to
/// something else everywhere it is wrong; `null` asks each platform for its own
/// text face, which is the whole point of the direction.
abstract final class Type {
  static const String display = 'Newsreader';

  /// Durations, positions, counts, queue indices.
  ///
  /// Tabular figures so a column of times does not shift as the seconds tick,
  /// which is the single most distracting thing a player can do.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static const TextStyle screenTitle = TextStyle(
    fontFamily: display,
    fontSize: 30,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );

  static const TextStyle nowPlaying = TextStyle(
    fontFamily: display,
    fontSize: 24,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: display,
    fontSize: 19,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// An episode title in a list. Platform face: these are scanned, not read.
  static const TextStyle rowTitle = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
  );

  static const TextStyle body = TextStyle(fontSize: 15, height: 1.45);

  static const TextStyle meta = TextStyle(
    fontSize: 13,
    height: 1.35,
    letterSpacing: -0.05,
    fontFeatures: tabular,
  );

  static const TextStyle label = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static const TextStyle control = TextStyle(
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
  );

  /// The one place a number is the content rather than an annotation.
  static const TextStyle timecode = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontFeatures: tabular,
    letterSpacing: 0,
  );
}
