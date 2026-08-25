import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/cuesheet_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'artwork.dart';

/// The top of a podcast's own screen.
///
/// The description is collapsed to four lines and expands on tap. Show notes
/// for a podcast run to several paragraphs of boilerplate, and burying the
/// episode list under them would be optimising the screen for the thing you
/// read once.
class PodcastHeader extends StatefulWidget {
  const PodcastHeader({
    required this.podcast,
    required this.description,
    required this.now,
    this.episodeCount = 0,
    this.unplayed = 0,
    this.onRefresh,
    this.refreshing = false,
    super.key,
  });

  final Podcast podcast;

  /// Passed in rather than read, like every other clock in this project: a
  /// component that calls `DateTime.now()` cannot be tested at a chosen
  /// instant, and "checked 3 days ago" is exactly the sort of string that
  /// needs to be.
  final DateTime now;

  /// Already plain text. Feeds put markup in here and unpicking it is a data
  /// concern — `cuesheet_ui` never learns that feeds are XML.
  final String? description;

  final int episodeCount;
  final int unplayed;
  final VoidCallback? onRefresh;
  final bool refreshing;

  @override
  State<PodcastHeader> createState() => _PodcastHeaderState();
}

class _PodcastHeaderState extends State<PodcastHeader> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);
    final podcast = widget.podcast;
    final description = widget.description;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Space.gutter, Space.lg, Space.gutter, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Artwork(
                url: podcast.artworkUrl,
                size: 96,
                title: podcast.title,
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      podcast.title,
                      style: Type.sectionTitle.copyWith(color: colors.ink),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (podcast.author != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        podcast.author!,
                        style: Type.meta.copyWith(color: colors.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: Space.sm),
                    Text(
                      metaLine([
                        '${widget.episodeCount} episodes',
                        if (widget.unplayed > 0) '${widget.unplayed} unplayed',
                        if (podcast.lastFetchedAt != null)
                          'checked ${formatPublished(podcast.lastFetchedAt, now: widget.now)}',
                      ]),
                      style: Type.meta.copyWith(color: colors.inkMuted),
                    ),
                    if (widget.onRefresh != null) ...[
                      const SizedBox(height: Space.xs),
                      TextButton(
                        onPressed: widget.refreshing ? null : widget.onRefresh,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: Space.sm, vertical: 0),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                            widget.refreshing ? 'Checking…' : 'Check for new'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Text(
                description,
                style: Type.body.copyWith(color: colors.inkMuted),
                maxLines: _expanded ? null : 4,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
