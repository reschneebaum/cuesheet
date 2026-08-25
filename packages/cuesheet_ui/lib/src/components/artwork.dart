import 'package:flutter/material.dart';

import '../theme/cuesheet_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Podcast or episode art.
///
/// Every path through this widget produces something square and the right
/// size, including the ones where there is no image: a placeholder that
/// reserves the space, a network failure, and an artwork URL the feed supplied
/// that does not resolve. Art that pops in and reflows the layout underneath a
/// finger is worse than art that arrives late.
class Artwork extends StatelessWidget {
  const Artwork({
    required this.url,
    required this.size,
    this.title,
    super.key,
  });

  final Uri? url;
  final double size;

  /// Used for the placeholder's initial, and for the accessible label.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);
    final radius = BorderRadius.circular(size < 80 ? 6 : 12);

    return Semantics(
      label: title == null ? 'Artwork' : 'Artwork for $title',
      image: true,
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: size,
          height: size,
          child: url == null
              ? _Placeholder(colors: colors, title: title, size: size)
              : Image.network(
                  url.toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) =>
                      _Placeholder(colors: colors, title: title, size: size),
                  // Held rather than faded in: the space is already reserved,
                  // and a cross-fade on a grid of tiles is a lot of motion for
                  // no information.
                  loadingBuilder: (context, child, progress) =>
                      progress == null
                          ? child
                          : _Placeholder(
                              colors: colors, title: title, size: size),
                ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.colors, required this.title, required this.size});

  final CuesheetColors colors;
  final String? title;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = (title ?? '').trim();
    return ColoredBox(
      color: colors.surfaceRaised,
      child: Center(
        child: initial.isEmpty
            ? Icon(Icons.podcasts, size: size * 0.3, color: colors.inkFaint)
            : Text(
                initial.characters.first.toUpperCase(),
                style: Type.screenTitle.copyWith(
                  color: colors.inkFaint,
                  fontSize: size * 0.34,
                ),
              ),
      ),
    );
  }
}
