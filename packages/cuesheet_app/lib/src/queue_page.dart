import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'queue_actions.dart';

class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider).value ?? QueueState.empty;
    final index = ref.watch(episodeIndexProvider).value ?? const {};
    final undoDepth = ref.watch(undoStackProvider).length;
    final displaced = ref.watch(displacedProvider).value ?? const [];
    final actions = ref.read(queueActionsProvider);

    String titleOf(EpisodeId id) =>
        index[id]?.episode.title ?? '(unknown ${id.value})';

    final items = queue.active?.items ?? const <EpisodeId>[];

    return ListView(
      children: [
        ListTile(
          title: Text(switch (queue.source) {
            null => 'Nothing playing',
            Detached(:final episode) => 'Playing detached: ${titleOf(episode)}',
            FromQueue() => 'Playing from queue: '
                '${queue.nowPlaying == null ? '—' : titleOf(queue.nowPlaying!)}',
          }),
          subtitle: Text(
            queue.isDetached
                // The property that makes "play just this" safe.
                ? 'The queue is untouched and will not advance.'
                : 'Position ${queue.position + 1} of ${items.length}',
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: undoDepth == 0 ? null : actions.undo,
                child: Text('Undo ($undoDepth)'),
              ),
              TextButton(
                onPressed: queue.active == null ||
                        queue.active!.kind == CuesheetKind.saved
                    ? null
                    : () => _promote(context, ref, queue.active!),
                child: const Text('Save queue'),
              ),
            ],
          ),
        ),
        const Divider(),
        if (items.isEmpty)
          const ListTile(title: Text('The queue is empty.'))
        else
          for (var i = 0; i < items.length; i++)
            ListTile(
              dense: true,
              leading: Text('${i + 1}'),
              title: Text(titleOf(items[i])),
              selected: !queue.isDetached && i == queue.position,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Move to end',
                    icon: const Icon(Icons.vertical_align_bottom, size: 18),
                    onPressed: () =>
                        actions.apply(MoveToEnd(items[i]), items),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        actions.apply(RemoveFromQueue(items[i]), items),
                  ),
                ],
              ),
            ),
        const Divider(),
        ListTile(
          title: const Text('Recently replaced queues'),
          subtitle: Text(displaced.isEmpty
              ? 'None — replacing a queue keeps the old one here.'
              : 'Restoring one is an ordinary save, not a special path.'),
        ),
        for (final sheet in displaced)
          ListTile(
            dense: true,
            title: Text('${sheet.items.length} episodes'),
            subtitle: Text([for (final i in sheet.items) titleOf(i)].join(', '),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: TextButton(
              onPressed: () => actions.restore(sheet),
              child: const Text('Restore'),
            ),
          ),
      ],
    );
  }

  Future<void> _promote(
      BuildContext context, WidgetRef ref, Cuesheet cuesheet) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save this queue'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    await ref.read(queueActionsProvider).promote(cuesheet, title);
  }
}

class SavedPage extends ConsumerWidget {
  const SavedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedCuesheetsProvider).value ?? const [];
    final index = ref.watch(episodeIndexProvider).value ?? const {};
    final actions = ref.read(queueActionsProvider);

    if (saved.isEmpty) {
      return const Center(
          child: Text('No saved cuesheets. Save a queue from the Queue tab.'));
    }

    return ListView(
      children: [
        for (final sheet in saved)
          ListTile(
            title: Text(sheet.title ?? '(untitled)'),
            subtitle: Text([
              for (final i in sheet.items)
                index[i]?.episode.title ?? i.value,
            ].join(', '), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: TextButton(
              onPressed: () => actions.apply(
                  ReplaceQueue(sheet.items), sheet.items),
              child: const Text('Play'),
            ),
          ),
      ],
    );
  }
}
