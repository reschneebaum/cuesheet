import 'package:cuesheet_data/cuesheet_data.dart' show plainText;
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_page.dart' show unplayedCountsProvider;
import 'providers.dart';
import 'queue_actions.dart';

/// One podcast, and its episodes.
class PodcastPage extends ConsumerStatefulWidget {
  const PodcastPage({required this.podcastId, super.key});

  final PodcastId podcastId;

  static Route<void> route(PodcastId id) =>
      MaterialPageRoute(builder: (_) => PodcastPage(podcastId: id));

  @override
  ConsumerState<PodcastPage> createState() => _PodcastPageState();
}

class _PodcastPageState extends ConsumerState<PodcastPage> {
  /// Newest first suits a chat show; oldest first suits anything serialised,
  /// and a listener starting a back catalogue should not have to scroll to the
  /// bottom of four hundred episodes to begin.
  bool _newestFirst = true;
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);
    final now = ref.watch(clockProvider)();
    final podcasts = ref.watch(podcastsProvider).value ?? const <Podcast>[];
    final podcast =
        podcasts.where((p) => p.id == widget.podcastId).firstOrNull;

    final episodes = ref
            .watch(podcastEpisodesProvider(
                (podcast: widget.podcastId, newestFirst: _newestFirst)))
            .value ??
        const <EpisodeView>[];

    final queue = ref.watch(queueProvider).value ?? QueueState.empty;
    final queued = queue.active?.items ?? const <EpisodeId>[];
    final visible = [for (final v in episodes) v.episode.id];

    final unplayed = ref.watch(unplayedCountsProvider)[widget.podcastId] ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('')),
      body: podcast == null
          ? const EmptyState(title: 'Not subscribed')
          : ListView.separated(
              itemCount: episodes.length + 2,
              separatorBuilder: (_, i) =>
                  i < 1 ? const SizedBox.shrink() : Divider(height: 1, color: colors.rule),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return PodcastHeader(
                    podcast: podcast,
                    // Feeds put markup in here; unpicking it is a data concern,
                    // so it happens on this side of the boundary and
                    // `cuesheet_ui` never learns that feeds are XML.
                    description: plainText(podcast.description),
                    now: now,
                    episodeCount: episodes.length,
                    unplayed: unplayed,
                    refreshing: _refreshing,
                    onRefresh: _refresh,
                  );
                }
                if (i == 1) {
                  return SectionHeader(
                    label: _newestFirst ? 'Newest first' : 'Oldest first',
                    trailing: TextButton(
                      onPressed: () =>
                          setState(() => _newestFirst = !_newestFirst),
                      child: Text(_newestFirst ? 'Oldest first' : 'Newest first'),
                    ),
                  );
                }

                final view = episodes[i - 2];
                final at = queued.indexOf(view.episode.id);
                return EpisodeTile(
                  view: view,
                  now: now,
                  // Repeating the podcast name on every row of its own screen
                  // is noise.
                  showPodcast: false,
                  queuePosition: at < 0 ? null : at + 1,
                  isPlaying: queue.nowPlaying == view.episode.id,
                  onTap: () => _choose(view, visible),
                );
              },
            ),
    );
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await ref.read(feedIngestionProvider).refresh(widget.podcastId);
    } on Object catch (error) {
      ref.read(ingestionLogProvider.notifier).add('refresh failed: $error');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _choose(EpisodeView view, List<EpisodeId> visible) async {
    final intent = await showIntentSheet(
      context,
      episodeTitle: view.episode.title,
      intents: episodeIntents(view.episode.id),
      queue: ref.read(queueProvider).value ?? QueueState.empty,
      visible: visible,
    );
    if (intent == null) return;
    await ref.read(queueActionsProvider).apply(intent, visible);
  }
}
