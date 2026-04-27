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

  // --- Glass / blur --------------------------------------------------------
  static const double blurLow = 10;
  static const double blurMid = 20;
  static const double blurHigh = 40;

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
