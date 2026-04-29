import 'package:flutter/material.dart';

/// Material 3-aligned width breakpoints used by every adaptive layout
/// in AWAtv.
///
/// Anchors:
///   * **phone**       (<600 dp): single-column, bottom navigation, dense
///                                content density.
///   * **tablet**      (600–900 dp): two-column where it makes sense
///                                (master/detail), bottom navigation
///                                still wins because portrait tablets
///                                are touch-first and short.
///   * **tabletLarge** (900–1100 dp): full master/detail with side rail,
///                                bigger media tiles, search results in
///                                three columns.
///   * **desktop**     (>=1100 dp): the existing desktop shell takes
///                                over with NavigationRail + persistent
///                                player; this constant matches
///                                `DesignTokens.desktopShellBreakpoint`
///                                exactly so the two layers stay aligned.
class Breakpoints {
  const Breakpoints._();

  /// Width below which we use the phone layout (single column, bottom nav).
  static const double phone = 600;

  /// Width above which we treat the device as a tablet (master/detail
  /// allowed, two-column lists OK).
  static const double tablet = 600;

  /// Width above which we treat the device as a *large* tablet —
  /// 3-column search, persistent rail, bigger poster grid.
  static const double tabletLarge = 900;

  /// Width at/above which the *desktop* shell (NavigationRail + custom
  /// chrome) replaces the mobile shell entirely.
  static const double desktop = 1100;
}

/// Form-factor classification — every adaptive widget should branch on
/// this enum, never on a raw width number, so the breakpoints can be
/// retuned in one place.
enum DeviceClass {
  /// Phones, smaller folded foldables.
  phone,

  /// Portrait tablets, landscape phones in split-screen.
  tablet,

  /// Landscape tablets, large foldables, ChromeOS in tablet mode.
  tabletLarge,

  /// Desktop/laptop windows. Reaches the desktop shell branch.
  desktop;

  /// True for tablet *or* tabletLarge — the common case for "use the
  /// adaptive 2/3-column variant".
  bool get isTablet =>
      this == DeviceClass.tablet || this == DeviceClass.tabletLarge;

  /// True for the larger tablet specifically — used to bump from 2 to 3
  /// columns in the search results grid.
  bool get isTabletLarge => this == DeviceClass.tabletLarge;
}

/// Resolve the active [DeviceClass] for the current MediaQuery.
///
/// Pure function so widgets can call it from `LayoutBuilder` builders
/// without round-tripping through Riverpod when they already know the
/// constraints. For BuildContext callers see [deviceClassFor].
DeviceClass deviceClassForWidth(double width) {
  if (width >= Breakpoints.desktop) return DeviceClass.desktop;
  if (width >= Breakpoints.tabletLarge) return DeviceClass.tabletLarge;
  if (width >= Breakpoints.tablet) return DeviceClass.tablet;
  return DeviceClass.phone;
}

/// Convenience wrapper for widgets that have a `BuildContext` in scope.
/// Reads `MediaQuery.sizeOf(context).width` so it rebuilds when the
/// window resizes (foldables, desktop chrome shrink).
DeviceClass deviceClassFor(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return deviceClassForWidth(width);
}
