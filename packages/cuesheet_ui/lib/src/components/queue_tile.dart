import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/cuesheet_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// One entry in the queue.
///
/// Distinct from [EpisodeTile] because the queue asks a different question. A
/// library list asks "do I want this?"; the queue asks "where is this, and is
/// it still ahead of me?" So the position is the leading element rather than a
/// badge, and everything behind the playhead is dimmed.
///
/// That dimming is the Phase 4 decision made visible: a finished episode stays
/// in the queue and the playhead moves past it (rule 1). The cuesheet is a
/// document, and this is what having read part of a document looks like.
class QueueTile extends StatelessWidget {
  const QueueTile({
    required this.view,
    required this.index,
    required this.now,
    this.isPlaying = false,
    this.isBehindPlayhead = false,
    this.onTap,
    this.handle,
    super.key,
  });

  final EpisodeView view;

  /// Zero-based. Displayed one-based, because nobody counts a running order
  /// from zero.
  final int index;

  final DateTime now;
  final bool isPlaying;

  /// Already passed. Not the same as finished — you can move the playhead over
  /// something without listening to it, and the queue should say so honestly.
  final bool isBehindPlayhead;

  final VoidCallback? onTap;

  /// The drag affordance, supplied by whatever list this sits in.
  ///
  /// Passed in rather than built here so `cuesheet_ui` never has to know that
  /// `ReorderableListView` exists, or that reordering is how the queue is
  /// edited at all.
  final Widget? handle;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);
    final episode = view.episode;

    final dimmed = isBehindPlayhead && !isPlaying;
    final titleColor = dimmed ? colors.inkMuted : colors.ink;

    return Semantics(
      button: onTap != null,
      label: metaLine([
        '${index + 1}.',
        episode.title,
        if (isPlaying) 'playing',
        if (dimmed) 'already passed',
      ]),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.gutter, Space.md, Space.sm, Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 26,
                child: isPlaying
                    ? Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(Icons.graphic_eq,
                            size: 16, color: colors.accent),
                      )
                    : Text(
                        '${index + 1}',
                        style: Type.timecode.copyWith(
                          color: dimmed ? colors.inkFaint : colors.inkMuted,
                        ),
                      ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.title,
                      style: Type.rowTitle.copyWith(color: titleColor),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metaLine([
                        view.podcastTitle,
                        describeProgress(view.listening,
                            episodeDuration: episode.duration, now: now),
                      ]),
                      style: Type.meta.copyWith(
                        color: dimmed ? colors.inkFaint : colors.inkMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (handle != null) ...[
                const SizedBox(width: Space.sm),
                IconTheme(
                  data: IconThemeData(color: colors.inkFaint, size: 20),
                  child: handle!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
