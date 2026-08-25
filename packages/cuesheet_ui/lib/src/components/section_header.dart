import 'package:flutter/material.dart';

import '../theme/cuesheet_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// A small label above a group, with an optional action on the right.
///
/// Uppercase and letter-spaced rather than large and bold: a heading in a list
/// is a signpost, and a signpost that competes with the content for weight has
/// misunderstood its job.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.label, this.trailing, super.key});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = CuesheetTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Space.gutter, Space.xl, Space.sm, Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: Type.label.copyWith(color: colors.inkFaint),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
