import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'podcast_page.dart';
import 'providers.dart';

/// Everything you subscribe to.
///
/// The one list in the app that leads with artwork, because it is the one list
/// where the picture is genuinely the fastest way to find what you meant.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final podcasts = ref.watch(podcastsProvider).value ?? const <Podcast>[];
    final unplayed = ref.watch(unplayedCountsProvider);

    if (podcasts.isEmpty) {
      return const EmptyState(
        title: 'Nothing subscribed yet',
        body: 'Find a show on the Feeds tab, or paste a feed URL. '
            'Subscribing fetches the whole back catalogue.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(Space.gutter),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // A maximum rather than a fixed column count: the same grid has to
        // work on a phone and in a desktop window three times as wide, and
        // artwork that stretches to fill four columns stops being scannable.
        maxCrossAxisExtent: 190,
        mainAxisSpacing: Space.lg,
        crossAxisSpacing: Space.lg,
        childAspectRatio: 0.72,
      ),
      itemCount: podcasts.length,
      itemBuilder: (context, i) {
        final podcast = podcasts[i];
        return PodcastTile(
          podcast: podcast,
          unplayed: unplayed[podcast.id] ?? 0,
          onTap: () =>
              Navigator.of(context).push(PodcastPage.route(podcast.id)),
        );
      },
    );
  }
}

/// How many unplayed episodes each subscription has.
///
/// Derived from the already-loaded episode index rather than counted in SQL.
/// That is fine while the harness holds every episode in memory anyway, and is
/// the first thing to move into a query when it does not.
final unplayedCountsProvider = Provider<Map<PodcastId, int>>((ref) {
  final index = ref.watch(episodeIndexProvider).value ?? const {};
  final now = ref.watch(clockProvider)();
  final counts = <PodcastId, int>{};

  for (final view in index.values) {
    if (view.episode.isOrphaned) continue;
    final state = listenStateOf(
      view.listening,
      episodeDuration: view.episode.duration,
      now: now,
    );
    if (state != ListenState.unplayed) continue;
    counts.update(view.episode.podcastId, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
});
