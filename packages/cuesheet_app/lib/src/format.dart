/// Harness-only formatting.
///
/// Everything a real screen needs is in `cuesheet_ui`. What is left here is the
/// one thing only the debug harness wants.
library;

/// Minute resolution, UTC, no localisation. The harness wants a timestamp it
/// can compare against a log line, not one it can read aloud.
String formatTimestamp(DateTime at) {
  final utc = at.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)}Z';
}
