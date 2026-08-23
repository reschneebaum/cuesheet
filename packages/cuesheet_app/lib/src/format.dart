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
