import 'package:flutter/material.dart';

import '../theme/cuesheet_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// What a list says when it has nothing in it.
///
/// Given a component of its own because an empty queue is not an error and
/// should not read as one, and because the sentence is doing real work: it is
/// usually the only place the app explains what a screen is *for*.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.title, this.body, this.action, super.key});

  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Type.sectionTitle.copyWith(color: colors.ink),
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: Space.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  body!,
                  style: Type.body.copyWith(color: colors.inkMuted),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Space.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
