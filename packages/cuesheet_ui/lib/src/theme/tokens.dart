import 'package:flutter/widgets.dart';

/// The palette, as one set of named values per theme.
///
/// Held in a plain class rather than pulled off `ColorScheme` because most of
/// these have no Material equivalent — "the colour a queued badge is" is not a
/// primary or a tertiary, and forcing it into that vocabulary would make every
/// use site a small act of translation.
@immutable
final class CuesheetColors {
  const CuesheetColors({
    required this.ground,
    required this.surface,
    required this.surfaceRaised,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.rule,
    required this.accent,
    required this.accentInk,
    required this.accentWash,
    required this.orphan,
  });

  /// Behind everything.
  final Color ground;

  /// Rows, sheets, cards.
  final Color surface;

  /// A sheet sitting above a surface.
  final Color surfaceRaised;

  final Color ink;
  final Color inkMuted;
  final Color inkFaint;

  /// Hairlines. One weight, everywhere.
  final Color rule;

  /// The single accent.
  ///
  /// Spent only on things the user authored or is about to: the playhead, the
  /// active intent, a queued position. Deliberately absent from anything the
  /// app decided on its own, which is what keeps it meaning something.
  final Color accent;
  final Color accentInk;
  final Color accentWash;

  /// An episode the feed dropped. Muted rather than alarming — an orphan is a
  /// fact about the feed, not a problem the user caused (§6).
  final Color orphan;

  /// A signal green would be wrong here: nothing in this app is a warning.
  static const CuesheetColors light = CuesheetColors(
    ground: Color(0xFFF4F5F4),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    ink: Color(0xFF14100F),
    inkMuted: Color(0xFF6A6764),
    inkFaint: Color(0xFF9A9793),
    rule: Color(0xFFE0E1DF),
    accent: Color(0xFF0E6F66),
    accentInk: Color(0xFFFFFFFF),
    accentWash: Color(0xFFE2F0EE),
    orphan: Color(0xFF8A7A5C),
  );

  static const CuesheetColors dark = CuesheetColors(
    ground: Color(0xFF0F1110),
    surface: Color(0xFF171A19),
    surfaceRaised: Color(0xFF1E2221),
    ink: Color(0xFFE9EAE8),
    inkMuted: Color(0xFF9AA09D),
    inkFaint: Color(0xFF6C7370),
    rule: Color(0xFF272B2A),
    accent: Color(0xFF5CC8BC),
    accentInk: Color(0xFF06201D),
    accentWash: Color(0xFF14302D),
    orphan: Color(0xFFB79E75),
  );
}

/// One spacing scale, used for everything.
///
/// Four-point steps, because the row heights this app needs land between the
/// eight-point grid's rungs and rounding them up wastes a third of a phone
/// screen on a list whose job is to be scanned.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// The left edge everything lines up on.
  static const double gutter = 16;
}

abstract final class Radii {
  static const Radius sheet = Radius.circular(14);
  static const Radius control = Radius.circular(8);
  static const Radius pill = Radius.circular(999);
}

abstract final class Motion {
  /// Short enough that it reads as response rather than animation. Anything
  /// longer on a list row starts to feel like the app is thinking.
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration sheet = Duration(milliseconds: 240);
  static const Curve standard = Curves.easeOutCubic;
}
