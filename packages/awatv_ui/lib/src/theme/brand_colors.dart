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
  /// Primary brand — electric purple, the hero accent.
  static const Color primary = Color(0xFF6C5CE7);

  /// Soft tint of primary, used for glass strokes and chip surfaces.
  static const Color primarySoft = Color(0xFF8C7BFF);

  /// Cyan-aqua accent — energising secondary, used for live indicators
  /// and progress strokes.
  static const Color secondary = Color(0xFF00D4FF);

  /// App canvas — near-black with a hint of indigo.
  static const Color background = Color(0xFF0A0D14);

  /// Raised surface — cards, list rows, sheet bodies.
  static const Color surface = Color(0xFF14181F);

  /// High-elevation surface — modals, dialogs, popovers.
  static const Color surfaceHigh = Color(0xFF1C2230);

  /// Outline / hairline strokes against [surface].
  static const Color outline = Color(0xFF2A3040);

  /// Subtle outline used inside glass surfaces.
  static const Color outlineGlass = Color(0x33FFFFFF);

  /// Destructive / error states.
  static const Color error = Color(0xFFFF4757);

  /// Confirmations, "live" pulses paired with [secondary].
  static const Color success = Color(0xFF26DE81);

  /// Caution states (parental, premium teaser).
  static const Color warning = Color(0xFFFFA502);

  /// Primary content on dark surfaces.
  static const Color onSurface = Color(0xFFE8EAF0);

  /// Muted secondary text on dark surfaces.
  static const Color onSurfaceMuted = Color(0xFF8A91A0);

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
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6C5CE7), Color(0xFF00D4FF)],
  );

  /// Premium / upsell — warm purple to magenta.
  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8C7BFF), Color(0xFFFF6CD3)],
  );

  /// Standard scrim used for image legibility (transparent → black).
  static const LinearGradient scrimGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00000000), Color(0xCC000000)],
  );

  // --- Aurora surface (premium IPTV depth) --------------------------------
  /// Top of the aurora canvas — deep night with an indigo wash.
  /// Picked to harmonise with [primary] (#6C5CE7) at very low chroma so
  /// large background fills don't fight the brand accent.
  static const Color surfaceAuroraTop = Color(0xFF1B1430);

  /// Bottom of the aurora canvas — black-blue. Pairs with
  /// [surfaceAuroraTop] on a vertical gradient to create the sense of
  /// depth referenced apps lean on for hero panels and player chrome.
  static const Color surfaceAuroraBot = Color(0xFF050810);

  // --- Functional accents -------------------------------------------------
  /// Distinct from [error] — used for the "LIVE" pulse, broadcast badges,
  /// active recording dots. Hotter than error red so the eye reads it as
  /// "right now" rather than "something is wrong".
  static const Color liveAccent = Color(0xFFFF3B5C);

  /// Warm gold used by rating pills, premium badges, awards.
  /// Perceptually balanced against the cool brand primary.
  static const Color goldRating = Color(0xFFFFC857);

  /// Online / connected indicator — lush emerald that reads as
  /// "available" without competing with the cyan secondary.
  static const Color emeraldOnline = Color(0xFF45D27A);

  // --- Glass tints --------------------------------------------------------
  /// Pre-mixed dark glass tint matching the blur app bar across surfaces.
  /// 0xCC = 80% alpha, base #0F1320 (a touch warmer than [background]).
  static const Color glassTintDark = Color(0xCC0F1320);

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
