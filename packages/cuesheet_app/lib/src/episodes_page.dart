import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'queue_actions.dart';

const _filters = <String, EpisodeFilter>{
  'All': AllOf([]),
  'Unplayed': ListenStateIs({ListenState.unplayed}),
  'Started': ListenStateIs({ListenState.started}),
  'Finished': ListenStateIs({ListenState.finished}),
  'Relisten': ListenStateIs({ListenState.relistenCandidate}),
  'Short': DurationBetween(max: Duration(minutes: 30)),
};

const _sorts = <String, List<SortSpec>>{
  'Newest': [SortSpec(SortField.publishedAt, descending: true)],
  'Oldest': [SortSpec(SortField.publishedAt)],
  'Last listened': [SortSpec(SortField.lastPlayedAt, descending: true)],
  'Most played': [SortSpec(SortField.playCount, descending: true)],
  'Shortest': [SortSpec(SortField.duration)],
  'Least left': [SortSpec(SortField.remainingTime)],
  'Title': [SortSpec(SortField.title)],
};

class EpisodesPage extends ConsumerWidget {
  const EpisodesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(querySelectionProvider);
    final episodes = ref.watch(episodesProvider);

    return Column(
      children: [
        _Controls(query: query),
        const Divider(height: 1),
        Expanded(
          child: episodes.when(
            // Plain text, not a spinner: an indeterminate progress indicator
            // animates forever, and `pumpAndSettle` in a widget test waits for
            // animations to stop. A debug harness does not need the spinner.
            loading: () => const Center(child: Text('Loading...')),
            error: (e, _) => Center(child: Text('$e')),
            data: (views) => views.isEmpty
                ? const Center(child: Text('Nothing matches.'))
                : _EpisodeList(views: views),
          ),
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.query});

  final EpisodeQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final podcasts = ref.watch(podcastsProvider).value ?? const <Podcast>[];
    final selectedPodcast = ref.watch(podcastFilterProvider);

    void select({EpisodeFilter? filter, List<SortSpec>? sort}) => ref
        .read(querySelectionProvider.notifier)
        .select(
          EpisodeQuery(
            filter: filter ?? query.filter,
            sort: sort ?? query.sort,
          ),
        );

    // Filters are values with real equality, so working out which preset is
    // active is just `==` — no parallel "selected index" state to drift.
    String? activeSort;
    for (final entry in _sorts.entries) {
      if (query.sort.isNotEmpty && entry.value.first == query.sort.first) {
        activeSort = entry.key;
      }
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final entry in _filters.entries)
                ChoiceChip(
                  label: Text(entry.key),
                  selected: query.filter == entry.value,
                  onSelected: (_) => select(filter: entry.value),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Scrolls sideways rather than wrapping. Wrapping would grow the
          // controls downward and eat the list; a podcast title is arbitrarily
          // long and would otherwise overflow the row.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('Sort: '),
                DropdownButton<String>(
                  value: activeSort,
                  hint: const Text('custom'),
                  items: [
                    for (final key in _sorts.keys)
                      DropdownMenuItem(value: key, child: Text(key)),
                  ],
                  onChanged: (key) =>
                      key == null ? null : select(sort: _sorts[key]),
                ),
                if (podcasts.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  const Text('Podcast: '),
                  // A dropdown rather than a chip per podcast: it costs no extra
                  // height, which keeps the list itself the tall thing on screen,
                  // and it still works at fifty subscriptions.
                  DropdownButton<PodcastId?>(
                    value: selectedPodcast,
                    hint: const Text('all'),
                    items: [
                      const DropdownMenuItem(child: Text('all')),
                      for (final podcast in podcasts)
                        DropdownMenuItem(
                          value: podcast.id,
                          child: Text(podcast.title),
                        ),
                    ],
                    onChanged: (id) =>
                        ref.read(podcastFilterProvider.notifier).select(id),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeList extends ConsumerWidget {
  const _EpisodeList({required this.views});

  final List<EpisodeView> views;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The on-screen order, captured once and handed to every intent. This is
    // what makes "play from here, downward" mean the list you are looking at.
    final visible = [for (final v in views) v.episode.id];
    final now = ref.watch(clockProvider)();
    final queue = ref.watch(queueProvider).value ?? QueueState.empty;
    final items = queue.active?.items ?? const <EpisodeId>[];
    final rungs = ref.watch(matchRungsProvider).value ?? const {};

    return ListView.separated(
      itemCount: views.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final view = views[index];
        final at = items.indexOf(view.episode.id);

        final tile = EpisodeTile(
          view: view,
          now: now,
          queuePosition: at < 0 ? null : at + 1,
          isPlaying: queue.nowPlaying == view.episode.id,
          // Tapping a tile opens the sheet rather than doing anything. Nothing
          // in this app changes the queue except an explicit, named intent, and
          // a tile that played on tap would be the first exception.
          onTap: () => _choose(context, ref, view, visible),
          onLongPress: () => _harnessTools(context, ref, view),
        );

        final rung = rungs[view.episode.id];
        if (rung == null) return tile;

        // Which rung of §6's ladder attached this episode. Diagnostic, not
        // product — so it is annotated around the tile here rather than built
        // into it, and `cuesheet_ui` never learns that ingestion exists.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tile,
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
              child: Text(
                'matched: ${rung.name}',
                style: Type.label.copyWith(
                    color: CuesheetTheme.of(context).inkFaint),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    EpisodeView view,
    List<EpisodeId> visible,
  ) async {
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

  /// Not product. Setting an episode to an arbitrary listening state by hand is
  /// the only way to exercise the §9 rules without listening to an hour of
  /// audio, so the tools stay — on a long press, where they are reachable
  /// without cluttering the row the rest of the design is about.
  Future<void> _harnessTools(
    BuildContext context,
    WidgetRef ref,
    EpisodeView view,
  ) async {
    final actions = ref.read(queueActionsProvider);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Advance 5 minutes'),
              subtitle: const Text('harness only'),
              onTap: () => Navigator.of(context).pop('advance'),
            ),
            ListTile(
              title: const Text('Mark unplayed'),
              subtitle: const Text('harness only'),
              onTap: () => Navigator.of(context).pop('reset'),
            ),
          ],
        ),
      ),
    );

    switch (choice) {
      case 'advance':
        await actions.advancePlayhead(view, const Duration(minutes: 5));
      case 'reset':
        await actions.resetListening(view);
    }
  }
}
