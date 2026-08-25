import 'package:flutter/material.dart';

import '../theme/cuesheet_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Back, play/pause, forward. The three controls a podcast actually needs.
///
/// No next-and-previous-track. The queue is edited by named intents, not by a
/// pair of arrows that silently move the playhead off what you were listening
/// to — and there is nowhere on this control for "and it stays where it was",
/// which is the guarantee the rest of the app is built on.
class TransportControls extends StatelessWidget {
  const TransportControls({
    required this.isPlaying,
    required this.onPlayPause,
    required this.onBack,
    required this.onForward,
    this.enabled = true,
    this.compact = false,
    this.backBy = const Duration(seconds: 15),
    this.forwardBy = const Duration(seconds: 30),
    super.key,
  });

  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final bool enabled;

  /// Sized for the mini player rather than the full screen.
  final bool compact;

  final Duration backBy;
  final Duration forwardBy;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);
    final ink = enabled ? colors.ink : colors.inkFaint;
    final small = compact ? 20.0 : 26.0;
    final big = compact ? 30.0 : 48.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Skip(
          seconds: backBy.inSeconds,
          icon: Icons.replay,
          size: small,
          color: ink,
          onPressed: enabled ? onBack : null,
          tooltip: 'Back ${backBy.inSeconds}s',
        ),
        SizedBox(width: compact ? Space.sm : Space.xl),
        IconButton(
          tooltip: isPlaying ? 'Pause' : 'Play',
          iconSize: big,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: big + 12, height: big + 12),
          onPressed: enabled ? onPlayPause : null,
          icon: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: enabled ? colors.accent : colors.inkFaint,
          ),
        ),
        SizedBox(width: compact ? Space.sm : Space.xl),
        _Skip(
          seconds: forwardBy.inSeconds,
          icon: Icons.refresh,
          size: small,
          color: ink,
          onPressed: enabled ? onForward : null,
          tooltip: 'Forward ${forwardBy.inSeconds}s',
        ),
      ],
    );
  }
}

/// A circular arrow with the interval written inside it.
///
/// The number matters: 15 and 30 are different gestures with different
/// purposes — one recovers a sentence you missed, the other skips an ad — and
/// an unlabelled arrow makes you learn which is which by trying.
class _Skip extends StatelessWidget {
  const _Skip({
    required this.seconds,
    required this.icon,
    required this.size,
    required this.color,
    required this.onPressed,
    required this.tooltip,
  });

  final int seconds;
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints:
            BoxConstraints.tightFor(width: size + 16, height: size + 16),
        onPressed: onPressed,
        icon: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: size, color: color),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  '$seconds',
                  style: Type.label.copyWith(
                    color: color,
                    fontSize: size * 0.38,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Playback speed, as a button that says the current rate.
class SpeedButton extends StatelessWidget {
  const SpeedButton({
    required this.speed,
    required this.onChanged,
    this.rates = const [1.0, 1.25, 1.5, 1.75, 2.0],
    super.key,
  });

  final double speed;
  final ValueChanged<double> onChanged;
  final List<double> rates;

  static String label(double rate) =>
      rate == rate.roundToDouble() ? '${rate.toInt()}×' : '$rate×';

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);

    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: speed,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final rate in rates)
          PopupMenuItem(value: rate, child: Text(label(rate))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.md, vertical: Space.sm),
        child: Text(
          label(speed),
          style: Type.control.copyWith(
            color: speed == 1.0 ? colors.inkMuted : colors.accent,
          ),
        ),
      ),
    );
  }
}
