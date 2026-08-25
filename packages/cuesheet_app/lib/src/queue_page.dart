import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'queue_actions.dart';

/// The queue, as the document the whole project argues it is.
///
/// Every entry keeps its place until an intent moves it, the playhead sits
/// among them rather than consuming them, and what has already gone past is
/// dimmed rather than deleted.
class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = CuesheetTheme.of(context);
    final queue = ref.watch(queueProvider).value ?? QueueState.empty;
    final index = ref.watch(episodeIndexProvider).value ?? const {};
    final now = ref.watch(clockProvider)();
    final actions = ref.read(queueActionsProvider);

    final items = queue.active?.items ?? const <EpisodeId>[];

    if (items.isEmpty) {
      return Column(
        children: [
          _Summary(queue: queue, index: index, now: now),
          const Expanded(
            child: EmptyState(
              title: 'Nothing queued',
              body:
                  'Choose an episode and say what should happen to it. '
                  'Nothing arrives here on its own.',
            ),
          ),
        ],
      );
    }

    return ReorderableListView.builder(
      // On desktop `ReorderableListView` adds a drag handle of its own, which
      // lands next to the one `QueueTile` was already given and reads as two
      // controls for one job. Ours stays, because it is the one that works on
      // touch as well.
      buildDefaultDragHandles: false,
      // Reordering is the one queue edit that is a direct manipulation rather
      // than a named choice from a sheet — but it is still an intent, and it
      // still goes through `applyIntent` like every other.
      onReorder: (from, to) => actions.apply(
        // Flutter reports the destination as an index into the list *before*
        // the item was lifted out; `ReorderQueue` wants it after. One
        // subtraction, and a wrong one is a silent off-by-one every time you
        // drag downward.
        ReorderQueue(from: from, to: to > from ? to - 1 : to),
        items,
      ),
      header: _Summary(queue: queue, index: index, now: now),
      footer: _Displaced(now: now, index: index),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final id = items[i];
        final view = index[id];
        return Column(
          key: ValueKey(id.value),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (i > 0) Divider(height: 1, color: colors.rule),
            if (view == null)
              ListTile(dense: true, title: Text('(missing ${id.value})'))
            else
              QueueTile(
                view: view,
                index: i,
                now: now,
                isPlaying: queue.nowPlaying == id && !queue.isDetached,
                isBehindPlayhead: i < queue.position,
                onTap: () => _choose(context, ref, view, items),
                handle: ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.all(Space.sm),
                    child: Icon(Icons.drag_handle),
                  ),
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
}

/// What is playing, how much is left, and the two things you can do to the
/// queue as a whole.
class _Summary extends ConsumerWidget {
  const _Summary({required this.queue, required this.index, required this.now});

  final QueueState queue;
  final Map<EpisodeId, EpisodeView> index;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = CuesheetTheme.of(context);
    final actions = ref.read(queueActionsProvider);
    final undoDepth = ref.watch(undoStackProvider).length;
    final items = queue.active?.items ?? const <EpisodeId>[];

    // Counts what is actually still to listen to, from the playhead on.
    // Including finished episodes would make a queue you have read to the end
    // report several hours ahead of you.
    var left = Duration.zero;
    var ahead = 0;
    for (var i = queue.position; i < items.length; i++) {
      final view = index[items[i]];
      if (view == null) continue;
      if (isFinished(view.listening, episodeDuration: view.episode.duration)) {
        continue;
      }
      ahead++;
      left +=
          remaining(view.listening, episodeDuration: view.episode.duration) ??
          Duration.zero;
    }

    // Where the playhead is. Worth saying even when nothing is playing — the
    // queue keeps its place, and a page that only reports the position while
    // audio is rolling hides the thing this app is most careful about.
    final where = items.isEmpty
        ? null
        : '#${queue.position + 1} of ${items.length}';

    final headline = switch (queue.source) {
      Detached() => 'Playing on its own',
      FromQueue() => where!,
      null when items.isEmpty => 'Nothing queued',
      // Stopped at the end is not the same as paused part-way, and a queue
      // that says "Paused" when there is nothing left to resume is lying in
      // the small way this app is about not doing.
      null when ahead == 0 => 'Reached the end',
      null => 'Not playing',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.sm,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // With no queue there is nothing to summarise, and the empty state
          // below is already saying so. Two of them saying it is one too many.
          if (items.isNotEmpty) ...[
            Text(headline, style: Type.screenTitle.copyWith(color: colors.ink)),
            const SizedBox(height: 2),
            Text(
              queue.isDetached
                  // The property that makes "play just this" safe, stated where
                  // it is true rather than explained in a settings screen — and
                  // naming the place the queue is still holding.
                  ? 'The queue is untouched at $where and will not advance.'
                  : metaLine([
                      // Already in the headline when playing from the queue.
                      if (queue.source is! FromQueue) where,
                      if (ahead > 0) '$ahead ahead',
                      if (left > Duration.zero) '${formatLength(left)} left',
                    ]),
              style: Type.meta.copyWith(color: colors.inkMuted),
            ),
          ],
          const SizedBox(height: Space.sm),
          Row(
            children: [
              TextButton(
                onPressed: undoDepth == 0 ? null : actions.undo,
                child: Text(undoDepth == 0 ? 'Undo' : 'Undo ($undoDepth)'),
              ),
              TextButton(
                onPressed:
                    queue.active == null ||
                        queue.active!.kind == CuesheetKind.saved
                    ? null
                    : () => _promote(context, ref, queue.active!),
                child: const Text('Save queue'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _promote(
    BuildContext context,
    WidgetRef ref,
    Cuesheet cuesheet,
  ) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save this queue'),
        // A promotion, not a copy: the thing you were listening to becomes the
        // thing you saved, so there is nothing to diverge (§7).
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    await ref.read(queueActionsProvider).promote(cuesheet, title);
  }
}

/// Queues that got replaced, kept rather than deleted (§5.4).
class _Displaced extends ConsumerWidget {
  const _Displaced({required this.now, required this.index});

  final DateTime now;
  final Map<EpisodeId, EpisodeView> index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = CuesheetTheme.of(context);
    final displaced = ref.watch(displacedProvider).value ?? const <Cuesheet>[];
    final actions = ref.read(queueActionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(label: 'Recently replaced'),
        if (displaced.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.xl,
            ),
            child: Text(
              'Replacing a queue keeps the old one here. Losing an '
              'accidentally-clobbered queue is one of the things this app '
              'exists to fix.',
              style: Type.meta.copyWith(color: colors.inkMuted),
            ),
          )
        else
          for (final sheet in displaced)
            ListTile(
              dense: true,
              title: Text(
                '${sheet.items.length} episodes',
                style: Type.rowTitle.copyWith(color: colors.ink),
              ),
              subtitle: Text(
                [
                  for (final id in sheet.items)
                    index[id]?.episode.title ?? id.value,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.meta.copyWith(color: colors.inkMuted),
              ),
              trailing: TextButton(
                onPressed: () => actions.restore(sheet),
                child: const Text('Restore'),
              ),
            ),
        const SizedBox(height: Space.xl),
      ],
    );
  }
}

/// Saved cuesheets. A promotion target, not a second model (§7).
class SavedPage extends ConsumerWidget {
  const SavedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = CuesheetTheme.of(context);
    final saved = ref.watch(savedCuesheetsProvider).value ?? const <Cuesheet>[];
    final index = ref.watch(episodeIndexProvider).value ?? const {};
    final actions = ref.read(queueActionsProvider);

    if (saved.isEmpty) {
      return const EmptyState(
        title: 'No saved cuesheets',
        body:
            'Saving a queue promotes it rather than copying it, so what you '
            'saved and what you were listening to can never drift apart.',
      );
    }

    return ListView.separated(
      itemCount: saved.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: colors.rule),
      itemBuilder: (context, i) {
        final sheet = saved[i];
        return ListTile(
          title: Text(
            sheet.title ?? '(untitled)',
            style: Type.rowTitle.copyWith(color: colors.ink),
          ),
          subtitle: Text(
            metaLine([
              '${sheet.items.length} episodes',
              [
                for (final id in sheet.items)
                  index[id]?.episode.title ?? id.value,
              ].join(' · '),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Type.meta.copyWith(color: colors.inkMuted),
          ),
          trailing: TextButton(
            onPressed: () =>
                actions.apply(ReplaceQueue(sheet.items), sheet.items),
            child: const Text('Play'),
          ),
        );
      },
    );
  }
}
