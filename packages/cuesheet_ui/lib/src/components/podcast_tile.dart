import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/cuesheet_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'artwork.dart';

/// One subscription, in the library grid.
///
/// Artwork-led, because this is the one list where the picture is genuinely the
/// fastest way to find the thing you meant. Everywhere else in the app the
/// title is.
class PodcastTile extends StatelessWidget {
  const PodcastTile({
    required this.podcast,
    this.unplayed = 0,
    this.onTap,
    super.key,
  });

  final Podcast podcast;

  /// Shown only when there is something to say. A subscription caught up is
  /// better represented by silence than by a zero.
  final int unplayed;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);

    return Semantics(
      button: onTap != null,
      label: metaLine([
        podcast.title,
        if (unplayed > 0) '$unplayed unplayed',
      ]),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Flexible, so the artwork gives way rather than the text being
            // clipped. A grid cell's height comes from whatever aspect ratio
            // the caller chose, and a title that needs two lines must not
            // depend on that guess being generous.
            Flexible(
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, box) => Artwork(
                    url: podcast.artworkUrl,
                    size: box.biggest.shortestSide,
                    title: podcast.title,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(
              podcast.title,
              style: Type.meta.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (unplayed > 0)
              Text(
                '$unplayed unplayed',
                style: Type.meta.copyWith(color: colors.inkMuted, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
