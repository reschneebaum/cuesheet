import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'queue_actions.dart';

/// The menu of things you can do to an episode.
///
/// Every entry's label, and whether it is enabled, comes from `previewIntent`
/// rather than from logic written here. That is the point (§5.5): this widget
/// is structurally incapable of offering something `applyIntent` will not do,
/// because it does not know the rules — it asks.
class IntentMenu extends ConsumerWidget {
  const IntentMenu({
    required this.episode,
    required this.visible,
    super.key,
  });

  final EpisodeId episode;

  /// The on-screen order at the moment of the tap. Required, because
  /// "from here, downward" is meaningless without it.
  final List<EpisodeId> visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider).value ?? QueueState.empty;

    final intents = <PlaybackIntent>[
      PlayJustThis(episode),
      PlayFromHere(episode, TraversalOrder.ascending),
      PlayFromHere(episode, TraversalOrder.descending),
      InsertNext(episode),
      AppendToQueue(episode),
      MoveToEnd(episode),
      RemoveFromQueue(episode),
    ];

    return PopupMenuButton<PlaybackIntent>(
      icon: const Icon(Icons.more_vert),
      onSelected: (intent) =>
          ref.read(queueActionsProvider).apply(intent, visible),
      itemBuilder: (context) => [
        for (final intent in intents)
          _entry(context, previewIntent(queue, intent, visible), intent),
      ],
    );
  }

  PopupMenuItem<PlaybackIntent> _entry(
    BuildContext context,
    IntentPreview preview,
    PlaybackIntent intent,
  ) {
    final muted = Theme.of(context).disabledColor;
    return PopupMenuItem(
      value: intent,
      // Disabled rather than hidden: seeing "Already #3 in queue" greyed out
      // tells you where the episode is. Hiding it tells you nothing.
      enabled: preview.willChange,
      // Stacked, not a Row: a Row with spaceBetween takes the full width it is
      // offered, and inside a popup menu that is more than there is.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(preview.verb),
          if (preview.detail != null)
            Text(
              preview.detail!,
              style: TextStyle(fontSize: 11, color: muted),
            ),
        ],
      ),
    );
  }
}
