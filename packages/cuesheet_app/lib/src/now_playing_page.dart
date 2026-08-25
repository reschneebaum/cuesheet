import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_controller.dart';
import 'providers.dart';
import 'queue_actions.dart';

/// The player.
///
/// The one screen where the display face earns its keep, and the only place
/// artwork is big enough to be worth looking at. Everything here reads from the
/// engine's ticks rather than the stored playhead — the database is written on
/// a five-second debounce (§9), and a scrubber that moved every five seconds
/// would look broken.
class NowPlayingPage extends ConsumerWidget {
  const NowPlayingPage({super.key});

  static Route<void> route() => MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const NowPlayingPage(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = CuesheetTheme.of(context);
    final controller = ref.watch(playbackControllerProvider);
    final tick = ref.watch(playbackTickProvider).value;
    final queue = ref.watch(queueProvider).value ?? QueueState.empty;
    final index = ref.watch(episodeIndexProvider).value ?? const {};

    final playing = queue.nowPlaying;
    final view = playing == null ? null : index[playing];
    final episode = view?.episode;

    final isPlaying = tick?.status == PlaybackStatus.playing;
    final position =
        tick?.position ?? view?.listening.position ?? Duration.zero;
    final duration = tick?.duration ?? episode?.duration;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          _source(queue),
          style: Type.meta.copyWith(color: colors.inkMuted),
        ),
        actions: [
          if (view != null)
            IconButton(
              tooltip: 'What to do with this',
              icon: const Icon(Icons.more_horiz),
              onPressed: () => _choose(context, ref, view, queue),
            ),
        ],
      ),
      body: SafeArea(
        child: view == null
            ? const EmptyState(
                title: 'Nothing loaded',
                body: 'Pick an episode and choose what should happen to it.',
              )
            : _Loaded(
                view: view,
                controller: controller,
                tick: tick,
                position: position,
                duration: duration,
                isPlaying: isPlaying,
              ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.view,
    required this.controller,
    required this.tick,
    required this.position,
    required this.duration,
    required this.isPlaying,
  });

  final EpisodeView view;
  final PlaybackController controller;
  final PlaybackTick? tick;
  final Duration position;
  final Duration? duration;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);
    final episode = view.episode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      child: Column(
        children: [
          // Takes whatever height the controls leave, and never more than its
          // own width. Sizing it off the width alone clips on a short window
          // and leaves a hole on a tall one.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Center(
                child: Artwork(
                  url: episode.artworkUrl,
                  size: box.biggest.shortestSide.clamp(0.0, 340.0),
                  title: view.podcastTitle,
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.xl),
          Text(
            episode.title,
            style: Type.nowPlaying.copyWith(color: colors.ink),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Space.xs),
          Text(
            view.podcastTitle,
            style: Type.body.copyWith(color: colors.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Space.xl),
          Scrubber(
            position: position,
            duration: duration,
            onSeek: controller.seekTo,
          ),
          const SizedBox(height: Space.md),
          TransportControls(
            isPlaying: isPlaying,
            onPlayPause: controller.togglePlayPause,
            onBack: () => controller.seekBy(const Duration(seconds: -15)),
            onForward: () => controller.seekBy(const Duration(seconds: 30)),
          ),
          const SizedBox(height: Space.sm),
          SpeedButton(
            speed: tick?.speed ?? 1.0,
            onChanged: controller.setSpeed,
          ),
          const SizedBox(height: Space.lg),
        ],
      ),
    );
  }
}

/// Where this audio is coming from, said plainly.
///
/// The detached case is the one that matters: it is the difference between
/// "this will carry on into your queue" and "this will not", and a player
/// that does not say which is which has hidden the guarantee (§5.3).
String _source(QueueState queue) {
  final items = queue.active?.items ?? const <EpisodeId>[];
  return switch (queue.source) {
    Detached() => 'Just this one · queue untouched',
    FromQueue() => 'From the queue · #${queue.position + 1} of ${items.length}',
    null => 'Not playing',
  };
}

Future<void> _choose(
  BuildContext context,
  WidgetRef ref,
  EpisodeView view,
  QueueState queue,
) async {
  // The visible list is the queue itself: that is the list this episode is
  // being considered in from here.
  final visible = queue.active?.items ?? [view.episode.id];
  final intent = await showIntentSheet(
    context,
    episodeTitle: view.episode.title,
    intents: episodeIntents(view.episode.id),
    queue: queue,
    visible: visible,
  );
  if (intent == null) return;
  await ref.read(queueActionsProvider).apply(intent, visible);
}
