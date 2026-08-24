import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'format.dart';
import 'playback_controller.dart';
import 'providers.dart';

/// Real transport controls, replacing the Phase 2 stand-in.
///
/// Reads the engine's ticks directly rather than the stored playhead: the
/// database is written on a five-second debounce (§9) and a scrubber that only
/// moved every five seconds would look broken.
class TransportBar extends ConsumerWidget {
  const TransportBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    final tick = ref.watch(playbackTickProvider).value;
    final queue = ref.watch(queueProvider).value ?? QueueState.empty;
    final index = ref.watch(episodeIndexProvider).value ?? const {};

    final playing = queue.nowPlaying;
    final view = playing == null ? null : index[playing];
    final status = tick?.status ?? PlaybackStatus.idle;
    final isPlaying = status == PlaybackStatus.playing;

    final position = tick?.position ?? Duration.zero;
    final duration = tick?.duration ?? view?.episode.duration;

    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    view?.episode.title ?? 'Nothing loaded',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${formatDuration(position)} / ${formatDuration(duration)}'
                    ' · ${status.name}'
                    // Detachment on the transport itself, not just the queue
                    // page: while detached, finishing will not advance (§5.3),
                    // and that should be visible while it is true.
                    '${queue.isDetached ? ' · detached' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Back 15s',
              icon: const Icon(Icons.replay_10),
              onPressed: playing == null
                  ? null
                  : () => controller.seekBy(const Duration(seconds: -15)),
            ),
            IconButton(
              tooltip: isPlaying ? 'Pause' : 'Play',
              iconSize: 32,
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed:
                  playing == null ? null : controller.togglePlayPause,
            ),
            IconButton(
              tooltip: 'Forward 30s',
              icon: const Icon(Icons.forward_30),
              onPressed: playing == null
                  ? null
                  : () => controller.seekBy(const Duration(seconds: 30)),
            ),
            DropdownButton<double>(
              value: tick?.speed ?? 1.0,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 1.0, child: Text('1×')),
                DropdownMenuItem(value: 1.25, child: Text('1.25×')),
                DropdownMenuItem(value: 1.5, child: Text('1.5×')),
                DropdownMenuItem(value: 2.0, child: Text('2×')),
              ],
              onChanged: (rate) =>
                  rate == null ? null : controller.setSpeed(rate),
            ),
          ],
        ),
      ),
    );
  }
}
