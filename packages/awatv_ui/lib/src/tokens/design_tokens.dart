import 'package:flutter/animation.dart';

/// Centralised design tokens for the AWAtv design system.
///
/// Anything that resembles a magic number in the UI should live here so
/// the whole product moves together when we tune the system.
class DesignTokens {
  const DesignTokens._();

  // --- Radii ---------------------------------------------------------------
  /// Tight corners: chips, micro-pills, inline tags.
  static const double radiusS = 8;

  /// Default for inputs, small cards, list rows.
  static const double radiusM = 12;

  /// Hero cards (poster, channel tile).
  static const double radiusL = 20;

  /// Sheets, modals, full-bleed cards.
  static const double radiusXL = 28;

  // --- Spacing scale -------------------------------------------------------
  static const double spaceXs = 4;
  static const double spaceS = 8;
  static const double spaceM = 16;
  static const double spaceL = 24;
  static const double spaceXl = 32;
  static const double spaceXxl = 48;

  // --- Motion --------------------------------------------------------------
  /// Snappy reaction (press feedback, ripple-like state changes).
  static const Duration motionFast = Duration(milliseconds: 150);

  /// Standard transitions, page fades, hero flights.
  static const Duration motionMedium = Duration(milliseconds: 350);

  /// Long, expressive transitions; sheets, hero between large surfaces.
  static const Duration motionSlow = Duration(milliseconds: 600);

  /// Material 3 emphasised standard easing.
  static const Curve motionStandard = Curves.easeInOutCubicEmphasized;

  /// Long-tail emphasised easing — perfect for hero/Sheet entrances.
  static const Curve motionEmphasized = Curves.easeOutQuint;

  // --- Motion (physics-tuned) ---------------------------------------------
  /// Quick spring-like bounce — used for press feedback, chip toggles,
  /// "chevron rotates as the section expands" micro-moments.
  static const Duration motionMicroBounce = Duration(milliseconds: 220);

  /// Side panel / sidebar slide-in cadence.
  static const Duration motionPanelSlide = Duration(milliseconds: 320);

  /// Hero flight time for poster → detail. Generous so the eye can
  /// follow the radius/elevation morph without snapping.
  static const Duration motionHeroFlight = Duration(milliseconds: 480);

  // --- Glass / blur --------------------------------------------------------
  static const double blurLow = 10;
  static const double blurMid = 20;
  static const double blurHigh = 40;

  /// Tuned blur sigmas for the premium IPTV-style glass surfaces. The
  /// existing [blurLow]/[blurMid]/[blurHigh] are kept for back-compat;
  /// new widgets should prefer these named values so we can tune the
  /// whole system from one place.
  static const double glassBlurStrong = 32;
  static const double glassBlurMedium = 18;
  static const double glassBlurLow = 8;

  /// Background fill alpha for glass surfaces (dark theme).
  static const double glassBgAlphaDark = 0.55;

  /// Background fill alpha for glass surfaces (light theme).
  static const double glassBgAlphaLight = 0.85;

  /// Stroke alpha for the 1px hairline that gives glass its "edge".
  static const double glassBorderAlpha = 0.6;

  // --- Shell layout --------------------------------------------------------
  /// Collapsed sidebar width — icon-only rail.
  static const double sidebarWidthCollapsed = 72;

  /// Expanded sidebar width — labels + counts visible.
  static const double sidebarWidthExpanded = 240;

  /// Persistent inline player bar height.
  static const double persistentPlayerBarHeight = 64;

  /// Width threshold below which the desktop sidebar shell falls back to
  /// the mobile bottom-nav HomeShell. Material 3 "expanded" breakpoint.
  static const double desktopShellBreakpoint = 1100;

  /// Width threshold above which the home screen shows a 3-pane layout
  /// (category tree + grid + EPG strip) instead of 2-pane.
  static const double tripleColumnBreakpoint = 1280;

  /// Side rail height for an avatar / profile pill at the bottom of the
  /// sidebar. Matches the persistent player bar height for visual rhythm.
  static const double sidebarFooterHeight = 64;

  /// Persistent player bar — thumbnail dimension (square).
  static const double persistentPlayerThumbSize = 40;

  /// Category tree row — single line, comfortable for keyboard navigation.
  static const double categoryTreeRowHeight = 36;

  /// Category tree pane width on wide layouts (the left pane of the
  /// 3-pane home).
  static const double categoryTreePaneWidth = 260;

  /// EPG strip width on triple-column home (the right pane).
  static const double epgStripPaneWidth = 320;

  // --- Aspect ratios -------------------------------------------------------
  /// Movie poster — TMDB & most catalogs.
  static const double posterAspect = 2 / 3;

  /// Backdrop / hero banner.
  static const double backdropAspect = 16 / 9;

  /// Channel tiles (logo + EPG strip).
  static const double channelTileAspect = 16 / 9;

  // --- Elevations ----------------------------------------------------------
  /// Surfaces resting on the canvas.
  static const double elevationLow = 1;

  /// Cards floating above content.
  static const double elevationMid = 4;

  /// Modals, persistent bottom sheets.
  static const double elevationHigh = 12;

  // --- Tap target ----------------------------------------------------------
  /// Minimum hit area; keep this for icon-only controls.
  static const double minTapTarget = 48;
}
