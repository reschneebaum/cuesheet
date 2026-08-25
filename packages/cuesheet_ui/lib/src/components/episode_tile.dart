import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/cuesheet_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// One episode, in a list.
///
/// Not `EpisodeRow`, which is taken: drift generates that name for the
/// `episodes` table's record class, and §10 is explicit that a row is not an
/// entity. The same discipline applies one layer further out — a row is a thing
/// in the database, so the thing on screen is a tile.
///
/// The most repeated surface in the app, so it earns the most restraint: a
/// title, one line of metadata, and whatever the queue already knows about this
/// episode. Nothing here is a button except the row itself.
///
/// **Queue membership is on the row, not behind a tap** (§5.5). An episode that
/// is queued says so and says where; one that is playing says that. Learning
/// the state of your own queue should not require opening anything.
class EpisodeTile extends StatelessWidget {
  const EpisodeTile({
    required this.view,
    required this.now,
    this.queuePosition,
    this.isPlaying = false,
    this.showPodcast = true,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final EpisodeView view;
  final DateTime now;

  /// One-based position in the active queue, or null if it is not queued.
  final int? queuePosition;
  final bool isPlaying;

  /// False inside a single podcast's own episode list, where repeating the
  /// podcast name on every row is noise.
  final bool showPodcast;

  final VoidCallback? onTap;

  /// Where the debug harness hangs its tools. Absent in the real app.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);
    final episode = view.episode;

    final meta = metaLine([
      if (showPodcast) view.podcastTitle,
      formatPublished(episode.publishedAt, now: now),
      describeProgress(view.listening,
          episodeDuration: episode.duration, now: now),
      if (view.listening.playCount > 1) '×${view.listening.playCount}',
    ]);

    return Semantics(
      button: onTap != null,
      label: metaLine([
        episode.title,
        meta,
        if (isPlaying) 'playing',
        if (queuePosition != null) 'queued at $queuePosition',
        if (episode.isOrphaned) 'no longer in the feed',
      ]),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.gutter, Space.md, Space.gutter, Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.title,
                      style: Type.rowTitle.copyWith(
                        color: episode.isOrphaned ? colors.inkMuted : colors.ink,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (episode.isOrphaned) ...[
                          _Tag(
                            label: 'NOT IN FEED',
                            color: colors.orphan,
                            // §6: kept because you did something to it. Stated
                            // plainly rather than hidden — an episode that
                            // silently vanishes is the bug, not the label.
                          ),
                          const SizedBox(width: Space.sm),
                        ],
                        Flexible(
                          child: Text(
                            meta,
                            style: Type.meta.copyWith(color: colors.inkMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isPlaying || queuePosition != null) ...[
                const SizedBox(width: Space.md),
                _QueueMark(
                  position: queuePosition,
                  isPlaying: isPlaying,
                  colors: colors,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Playing beats queued: an episode can be both, and "playing" is the more
/// urgent fact.
class _QueueMark extends StatelessWidget {
  const _QueueMark({
    required this.position,
    required this.isPlaying,
    required this.colors,
  });

  final int? position;
  final bool isPlaying;
  final CuesheetColors colors;

  @override
  Widget build(BuildContext context) {
    if (isPlaying) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(Icons.graphic_eq, size: 17, color: colors.accent),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.accentWash,
        borderRadius: const BorderRadius.all(Radii.pill),
      ),
      child: Text(
        '$position',
        style: Type.label.copyWith(color: colors.accent),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: const BorderRadius.all(Radii.control),
        ),
        child: Text(label, style: Type.label.copyWith(color: color, fontSize: 9)),
      );
}
