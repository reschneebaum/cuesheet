import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/cuesheet_theme.dart';
import '../theme/typography.dart';

/// The playhead, and the only control that can move it to an arbitrary point.
///
/// While a drag is in progress the widget shows the dragged value and ignores
/// incoming positions. Without that, every tick from the engine yanks the thumb
/// back under the finger holding it — the position updates five times a second,
/// and the engine has not been told about the drag yet.
class Scrubber extends StatefulWidget {
  const Scrubber({
    required this.position,
    required this.duration,
    required this.onSeek,
    this.enabled = true,
    super.key,
  });

  final Duration position;

  /// Null when the feed never said and the engine has not worked it out yet.
  /// The track is inert rather than hidden: something is playing, and the
  /// absence of a length is worth seeing.
  final Duration? duration;

  final ValueChanged<Duration> onSeek;
  final bool enabled;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);
    final total = widget.duration?.inMilliseconds.toDouble() ?? 0;
    final usable = widget.enabled && total > 0;

    // Elapsed is known even when the length is not, so it is read off the
    // position rather than off the track. Clamping it to a total of zero would
    // throw away the one number we actually have.
    final elapsed = _dragging ?? widget.position.inMilliseconds.toDouble();
    final shown = Duration(milliseconds: elapsed.round());

    final value = usable ? elapsed.clamp(0, total).toDouble() : 0.0;
    final left = widget.duration == null
        ? null
        : widget.duration! - shown;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            activeTrackColor: colors.accent,
            inactiveTrackColor: colors.rule,
            thumbColor: colors.accent,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            overlayColor: colors.accentWash,
            trackShape: const RoundedRectSliderTrackShape(),
            disabledActiveTrackColor: colors.rule,
            disabledInactiveTrackColor: colors.rule,
            disabledThumbColor: colors.inkFaint,
          ),
          child: Slider(
            value: value,
            max: total <= 0 ? 1 : total,
            onChanged: usable
                ? (v) => setState(() => _dragging = v)
                : null,
            // Committed on release, not continuously: seeking on every frame of
            // a drag would have the engine chasing the finger across the file.
            onChangeEnd: usable
                ? (v) {
                    widget.onSeek(Duration(milliseconds: v.round()));
                    setState(() => _dragging = null);
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(shown),
                  style: Type.timecode.copyWith(color: colors.inkMuted)),
              Text(
                left == null ? '--:--' : '-${formatDuration(left)}',
                style: Type.timecode.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
