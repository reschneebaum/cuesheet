import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'format.dart';
import 'intent_menu.dart';
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
    void select({EpisodeFilter? filter, List<SortSpec>? sort}) =>
        ref.read(querySelectionProvider.notifier).select(EpisodeQuery(
              filter: filter ?? query.filter,
              sort: sort ?? query.sort,
            ));

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
          Row(
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
            ],
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

    return ListView.separated(
      itemCount: views.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final view = views[index];
        final state = listenStateOf(view.listening,
            episodeDuration: view.episode.duration, now: now);
        final queued = queue.active?.items.indexOf(view.episode.id) ?? -1;
        final playing = queue.nowPlaying == view.episode.id;

        return ListTile(
          dense: true,
          leading: playing ? const Icon(Icons.volume_up, size: 18) : null,
          title: Text(view.episode.title),
          subtitle: Text(
            '${view.podcastTitle} · ${describeState(state)} · '
            '${formatDuration(view.listening.position)}'
            ' / ${formatDuration(view.episode.duration)}'
            '${view.listening.playCount > 0 ? ' · ×${view.listening.playCount}' : ''}'
            // Queue membership on the row itself, not hidden behind a tap.
            '${queued >= 0 ? ' · queued #${queued + 1}' : ''}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Advance 5 minutes (stands in for playback)',
                icon: const Icon(Icons.fast_forward, size: 18),
                onPressed: () => ref
                    .read(queueActionsProvider)
                    .advancePlayhead(view, const Duration(minutes: 5)),
              ),
              IconButton(
                tooltip: 'Mark unplayed',
                icon: const Icon(Icons.restart_alt, size: 18),
                onPressed: () =>
                    ref.read(queueActionsProvider).resetListening(view),
              ),
              IntentMenu(episode: view.episode.id, visible: visible),
            ],
          ),
        );
      },
    );
  }
}
