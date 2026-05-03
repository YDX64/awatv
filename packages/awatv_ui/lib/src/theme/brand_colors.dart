import 'package:awatv_ui/awatv_ui.dart' show AppTheme;
import 'package:awatv_ui/src/theme/app_theme.dart' show AppTheme;
import 'package:flutter/material.dart';

/// AWAtv brand palette.
///
/// These are the source-of-truth swatches. Widgets should not read them
/// directly — instead they consume `Theme.of(context).colorScheme`,
/// which is seeded from these in [AppTheme].
class BrandColors {
  const BrandColors._();

  // --- Dark theme (default) -----------------------------------------------
  // Cherry-red Netflix-inspired palette ported 1:1 from the Streas
  // mobile app (`/tmp/Streas/artifacts/iptv-app/constants/colors.ts`).
  // The previous electric-purple+cyan brand tokens are preserved as
  // [legacyAuroraPrimary]/[legacyAuroraSecondary] below for any
  // user-toggleable theme presets that want to bring them back.

  /// Primary brand — cherry crimson, hero accent + LIVE indicator.
  /// Streas: `#E11D48`.
  static const Color primary = Color(0xFFE11D48);

  /// Soft tint of primary — used for glass strokes, chip surfaces, and
  /// pressed-state ripples. Mid-cherry, slightly lifted.
  static const Color primarySoft = Color(0xFFBE123C);

  /// Deep tone of primary — for dark gradient stops and pressed
  /// foreground states. Streas calls this `CHERRY_DARK` (`#9F1239`).
  static const Color primaryDark = Color(0xFF9F1239);

  /// Secondary accent — Streas collapses everything onto cherry, so we
  /// alias secondary to primary by default. Anything that wants a true
  /// chroma contrast can reach for [emeraldOnline] or [goldRating].
  static const Color secondary = Color(0xFFE11D48);

  /// App canvas — pure near-black, no indigo tint.
  /// Streas: `#0a0a0a`.
  static const Color background = Color(0xFF0A0A0A);

  /// Raised surface — cards, list rows, sheet bodies.
  /// Streas: `#141414`.
  static const Color surface = Color(0xFF141414);

  /// High-elevation surface — modals, dialogs, popovers.
  /// Streas: `#1c1c1c`.
  static const Color surfaceHigh = Color(0xFF1C1C1C);

  /// Outline / hairline strokes against [surface].
  /// Streas: `#282828`.
  static const Color outline = Color(0xFF282828);

  /// Subtle outline used inside glass surfaces.
  static const Color outlineGlass = Color(0x33FFFFFF);

  /// Destructive / error states. Slightly hotter than Streas' cherry so
  /// errors visually separate from "live" indicators.
  static const Color error = Color(0xFFEF4444);

  /// Confirmations, success pulses, "available" indicators.
  /// Kept emerald-fresh; Streas has no separate green so we lean on the
  /// existing AWAtv tone.
  static const Color success = Color(0xFF26DE81);

  /// Caution / premium-tier states. Streas' palette uses gold (`#f59e0b`).
  static const Color warning = Color(0xFFF59E0B);

  /// Primary content on dark surfaces — Streas pure white.
  static const Color onSurface = Color(0xFFFFFFFF);

  /// Muted secondary text on dark surfaces.
  /// Streas: `mutedForeground = #808080`.
  static const Color onSurfaceMuted = Color(0xFF808080);

  // --- Legacy aurora palette (pre-Streas) ---------------------------------
  // Kept for the custom theme builder so users who prefer the original
  // electric-purple aesthetic can opt back in. Read these only from
  // theme presets, not from regular widgets.
  static const Color legacyAuroraPrimary = Color(0xFF6C5CE7);
  static const Color legacyAuroraSecondary = Color(0xFF00D4FF);
  static const Color legacyAuroraSurface = Color(0xFF14181F);
  static const Color legacyAuroraSurfaceHigh = Color(0xFF1C2230);

  // --- Light theme variants -----------------------------------------------
  /// Light mode canvas — soft neutral, never pure white.
  static const Color lightBackground = Color(0xFFF6F7FB);

  /// Light mode raised surface.
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// Light mode high surface.
  static const Color lightSurfaceHigh = Color(0xFFF0F2F8);

  /// Light mode outline.
  static const Color lightOutline = Color(0xFFD9DEEA);

  /// Primary content on light surfaces.
  static const Color onLightSurface = Color(0xFF0F1320);

  /// Muted secondary text on light surfaces.
  static const Color onLightSurfaceMuted = Color(0xFF5A6376);

  // --- Decorative gradients -----------------------------------------------
  /// Brand gradient — used on hero CTAs, splash, premium chips.
  /// Cherry crimson → cherry dark for a cinematic Netflix-style ramp.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE11D48), Color(0xFF9F1239)],
  );

  /// Premium / upsell — gold to cherry, the "movie-ticket" premium look.
  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFE11D48)],
  );

  /// Standard scrim used for image legibility (transparent → black).
  static const LinearGradient scrimGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00000000), Color(0xCC000000)],
  );

  // --- Aurora surface (legacy — pre-Streas) -------------------------------
  // Streas-mode flattens the canvas to pure black so these are kept only
  // for the legacy aurora theme preset. Active widgets should NOT read
  // these — read [background] for surfaces.
  /// Top of the aurora canvas (legacy preset only).
  static const Color surfaceAuroraTop = Color(0xFF0A0A0A);

  /// Bottom of the aurora canvas (legacy preset only).
  static const Color surfaceAuroraBot = Color(0xFF000000);

  // --- Functional accents -------------------------------------------------
  /// "LIVE" pulse, broadcast badges, active recording dots. In Streas
  /// mode this collapses onto [primary] so live indicators feel
  /// branded rather than competing.
  static const Color liveAccent = Color(0xFFE11D48);

  /// Warm gold used by rating pills, premium badges, awards.
  /// Streas: `gold = #f59e0b`.
  static const Color goldRating = Color(0xFFF59E0B);

  /// Online / connected indicator — emerald that reads as
  /// "available" without competing with the cherry primary.
  static const Color emeraldOnline = Color(0xFF45D27A);

  // --- Glass tints --------------------------------------------------------
  /// Pre-mixed dark glass tint matching the blur app bar across surfaces.
  /// 0xCC = 80% alpha, base #0a0a0a so glass blends with Streas canvas
  /// instead of leaving a milky purple wash.
  static const Color glassTintDark = Color(0xCC0A0A0A);

  /// Pre-mixed light glass tint — slightly cool off-white to keep glass
  /// feeling "frosted" rather than "milky".
  static const Color glassTintLight = Color(0xCCF8F8FB);

  // --- Gradients (additional) ---------------------------------------------
  /// Aurora vertical gradient — drop in as a `Container.decoration` for
  /// the app shell background or hero panels.
  static const LinearGradient auroraGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [surfaceAuroraTop, surfaceAuroraBot],
  );
}
