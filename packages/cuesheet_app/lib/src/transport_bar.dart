import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'now_playing_page.dart';
import 'playback_controller.dart';
import 'providers.dart';

/// The mini player, pinned under every tab.
///
/// Deliberately not a scrubber. At this size a drag target three pixels tall is
/// a way to seek by accident, and seeking by accident is the kind of surprise
/// this app is about. It shows where you are and lets you stop; moving the
/// playhead is what the full screen is for.
class TransportBar extends ConsumerWidget {
  const TransportBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = CuesheetTheme.of(context);
    final controller = ref.watch(playbackControllerProvider);
    final tick = ref.watch(playbackTickProvider).value;
    final queue = ref.watch(queueProvider).value ?? QueueState.empty;
    final index = ref.watch(episodeIndexProvider).value ?? const {};

    final playing = queue.nowPlaying;
    final view = playing == null ? null : index[playing];
    final isPlaying = tick?.status == PlaybackStatus.playing;
    final position = tick?.position ?? view?.listening.position ?? Duration.zero;
    final duration = tick?.duration ?? view?.episode.duration;

    final progress = (duration == null || duration.inMilliseconds <= 0)
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A hairline of progress instead of a control: readable at a glance,
          // impossible to drag by mistake.
          SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: colors.rule,
              valueColor: AlwaysStoppedAnimation(colors.accent),
            ),
          ),
          InkWell(
            onTap: view == null
                ? null
                : () => Navigator.of(context).push(NowPlayingPage.route()),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.md, Space.sm, Space.sm, Space.sm),
              child: Row(
                children: [
                  Artwork(
                    url: view?.episode.artworkUrl,
                    size: 38,
                    title: view?.podcastTitle,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          view?.episode.title ?? 'Nothing loaded',
                          style: Type.rowTitle.copyWith(
                            color: view == null ? colors.inkMuted : colors.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          metaLine([
                            view?.podcastTitle,
                            if (duration != null)
                              '-${formatDuration(duration - position)}',
                            // Detachment stated wherever it is true: while
                            // detached, finishing will not advance the queue.
                            if (queue.isDetached) 'just this one',
                          ]),
                          style: Type.meta.copyWith(color: colors.inkMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  TransportControls(
                    compact: true,
                    enabled: view != null,
                    isPlaying: isPlaying,
                    onPlayPause: controller.togglePlayPause,
                    onBack: () =>
                        controller.seekBy(const Duration(seconds: -15)),
                    onForward: () =>
                        controller.seekBy(const Duration(seconds: 30)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
