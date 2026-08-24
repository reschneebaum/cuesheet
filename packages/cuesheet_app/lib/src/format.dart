import 'package:cuesheet_domain/cuesheet_domain.dart';

String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String describeState(ListenState state) => switch (state) {
      ListenState.unplayed => 'unplayed',
      ListenState.started => 'started',
      ListenState.finished => 'finished',
      ListenState.relistenCandidate => 'relisten',
    };

/// Minute resolution, UTC, no localisation. The debug harness wants a
/// timestamp it can compare against a log line, not one it can read aloud.
String formatTimestamp(DateTime at) {
  final utc = at.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)}Z';
}
