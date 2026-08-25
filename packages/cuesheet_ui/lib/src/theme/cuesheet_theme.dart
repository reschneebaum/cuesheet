import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Hands [CuesheetColors] down the tree.
///
/// An `InheritedWidget` rather than a static, so a widget test can wrap one
/// component in either theme and assert what it renders without a whole app
/// around it.
class CuesheetTheme extends InheritedWidget {
  const CuesheetTheme({
    required this.colors,
    required super.child,
    super.key,
  });

  final CuesheetColors colors;

  static CuesheetColors of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<CuesheetTheme>();
    assert(theme != null, 'No CuesheetTheme found. Wrap the app in one.');
    return theme!.colors;
  }

  @override
  bool updateShouldNotify(CuesheetTheme oldWidget) =>
      oldWidget.colors != colors;
}

/// Material's [ThemeData], derived from our tokens rather than the other way
/// round.
///
/// Material is the widget kit, not the look. Everything that would announce it
/// — elevation, ripples, filled surfaces, the 56-pixel app bar — is turned off
/// here, once, so no component has to remember to.
ThemeData cuesheetThemeData(CuesheetColors colors, Brightness brightness) {
  final base = ThemeData(brightness: brightness, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: colors.ground,
    canvasColor: colors.surface,
    dividerColor: colors.rule,
    colorScheme: base.colorScheme.copyWith(
      primary: colors.accent,
      onPrimary: colors.accentInk,
      surface: colors.surface,
      onSurface: colors.ink,
    ),
    // No ripple. On iOS a spreading circle from the tap point reads as an
    // Android app wearing a costume.
    splashFactory: NoSplash.splashFactory,
    highlightColor: colors.accentWash,
    textTheme: base.textTheme.apply(
      bodyColor: colors.ink,
      displayColor: colors.ink,
    ),
    dividerTheme: DividerThemeData(
      color: colors.rule,
      thickness: 1,
      space: 1,
      indent: Space.gutter,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.ground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: Type.sectionTitle.copyWith(color: colors.ink),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: colors.rule,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radii.sheet),
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      iconColor: colors.inkMuted,
      textColor: colors.ink,
    ),
    iconTheme: IconThemeData(color: colors.inkMuted, size: 20),
  );
}
