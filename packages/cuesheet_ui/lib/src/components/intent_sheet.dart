import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter/material.dart';

import '../theme/cuesheet_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The one place in the app with any personality, and the one place the whole
/// thesis is visible at once.
///
/// Every way to change the queue is a named intent, so every way to change the
/// queue is a row here. Each row's label, and whether it will do anything at
/// all, comes from [previewIntent] — the UI is **not permitted** to invent
/// either (§5.5). A control reading "Move to end" that then does nothing has
/// lied, and this sheet is structurally incapable of it: the same function that
/// applies the intent is the one that wrote the label.
///
/// Intents that would change nothing are shown rather than hidden, greyed with
/// the reason ("Already #3 in queue"). Hiding them would make the queue's state
/// something you have to remember instead of something you can read.
class IntentSheet extends StatelessWidget {
  const IntentSheet({
    required this.episodeTitle,
    required this.intents,
    required this.queue,
    required this.visible,
    required this.onChosen,
    super.key,
  });

  /// Shown at the top, so it is never ambiguous which episode is about to be
  /// acted on. The sheet is opened from a list; the row that opened it may
  /// well be behind the sheet.
  final String episodeTitle;

  /// In offer order. The caller decides which are relevant to the surface it
  /// was opened from; this decides nothing except how they read.
  final List<PlaybackIntent> intents;

  final QueueState queue;

  /// The on-screen order at the moment of the tap. "From here, descending" is
  /// meaningless without it (§5.2).
  final List<EpisodeId> visible;

  final ValueChanged<PlaybackIntent> onChosen;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.xl, Space.xs, Space.xl, Space.lg),
            child: Text(
              episodeTitle,
              style: Type.sectionTitle.copyWith(color: colors.ink),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.rule, indent: 0),
          for (final intent in intents)
            _IntentTile(
              preview: previewIntent(queue, intent, visible),
              colors: colors,
              onTap: () => onChosen(intent),
            ),
          const SizedBox(height: Space.sm),
        ],
      ),
    );
  }
}

class _IntentTile extends StatelessWidget {
  const _IntentTile({
    required this.preview,
    required this.colors,
    required this.onTap,
  });

  final IntentPreview preview;
  final CuesheetColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = preview.willChange;

    return Semantics(
      button: enabled,
      enabled: enabled,
      label: preview.detail == null
          ? preview.verb
          : '${preview.verb}, ${preview.detail}',
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.xl, vertical: Space.md + 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  preview.verb,
                  style: Type.control.copyWith(
                    color: enabled ? colors.ink : colors.inkFaint,
                  ),
                ),
              ),
              if (preview.detail != null)
                Text(
                  preview.detail!,
                  style: Type.meta.copyWith(
                    // The detail is the reason, so it stays legible even when
                    // the control it explains is not offered.
                    color: enabled ? colors.inkMuted : colors.inkFaint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The intents an episode row offers, in the order they should read.
///
/// Play first because it is what most taps want; the two queue-building
/// intents next; the corrective ones last. `MoveToEnd` sits beside
/// `AppendToQueue` rather than replacing it — they are different things to
/// want, and the sheet says which one is available rather than swapping one
/// for the other behind the reader's back (§5.1).
List<PlaybackIntent> episodeIntents(EpisodeId episode) => [
      PlayJustThis(episode),
      PlayFromHere(episode, TraversalOrder.ascending),
      PlayFromHere(episode, TraversalOrder.descending),
      InsertNext(episode),
      AppendToQueue(episode),
      MoveToEnd(episode),
      RemoveFromQueue(episode),
    ];

/// Opens the sheet and completes with the chosen intent, or null if dismissed.
Future<PlaybackIntent?> showIntentSheet(
  BuildContext context, {
  required String episodeTitle,
  required List<PlaybackIntent> intents,
  required QueueState queue,
  required List<EpisodeId> visible,
}) =>
    showModalBottomSheet<PlaybackIntent>(
      context: context,
      // The sheet is a decision, and the list behind it is the context for
      // that decision. Keeping it visible is the point of not going full-screen.
      isScrollControlled: true,
      builder: (context) => IntentSheet(
        episodeTitle: episodeTitle,
        intents: intents,
        queue: queue,
        visible: visible,
        onChosen: (intent) => Navigator.of(context).pop(intent),
      ),
    );
