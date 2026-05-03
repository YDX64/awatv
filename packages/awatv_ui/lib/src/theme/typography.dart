import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AWAtv typography scale.
///
/// Built on top of the Material 3 type ramp but tightened for a premium
/// streaming feel: display sizes are slightly compressed in letter-spacing,
/// body sizes slightly relaxed for readability on TV at distance.
///
/// Streas-mode (the default) uses **Inter** — a humanist sans optimised
/// for screens that ports cleanly across web/native/desktop without
/// font-substitution drift between platforms. We pull it through
/// `google_fonts` which caches the file after first launch.
///
/// We resolve concrete `TextStyle`s against a [ColorScheme] so the same
/// scale works for both dark and light themes.
class AppTypography {
  const AppTypography._();

  /// Primary font family identifier. Streas shipping name.
  static const String primaryFamily = 'Inter';

  /// Build a complete `TextTheme` from a colour scheme.
  ///
  /// The scheme drives text colours; structure (weight / size / spacing)
  /// is shared between dark and light.
  static TextTheme textTheme(ColorScheme scheme) {
    final onSurface = scheme.onSurface;
    final onSurfaceMuted = scheme.onSurface.withValues(alpha: 0.65);

    TextStyle base(double size, FontWeight weight, double letterSpacing,
        {double? height, Color? color}) {
      // GoogleFonts.inter wraps a TextStyle and lazy-loads the ttf in
      // the background. The first frame uses the platform default while
      // the asset downloads + caches — invisible on subsequent runs.
      return GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
        color: color ?? onSurface,
      );
    }

    return TextTheme(
      // Display — used very rarely (hero overlays, splash).
      displayLarge: base(57, FontWeight.w700, -1.5, height: 1.05),
      displayMedium: base(45, FontWeight.w700, -1, height: 1.1),
      displaySmall: base(36, FontWeight.w700, -0.5, height: 1.15),

      // Headline — page titles, modal titles.
      headlineLarge: base(32, FontWeight.w700, -0.4, height: 1.2),
      headlineMedium: base(28, FontWeight.w700, -0.3, height: 1.22),
      headlineSmall: base(24, FontWeight.w600, -0.2, height: 1.25),

      // Title — card / row headers, section labels.
      titleLarge: base(22, FontWeight.w600, 0, height: 1.3),
      titleMedium: base(16, FontWeight.w600, 0.1, height: 1.35),
      titleSmall: base(14, FontWeight.w600, 0.1, height: 1.4),

      // Body — primary running text.
      bodyLarge: base(16, FontWeight.w400, 0.15, height: 1.5),
      bodyMedium: base(14, FontWeight.w400, 0.2, height: 1.5),
      bodySmall: base(12, FontWeight.w400, 0.25, height: 1.45,
          color: onSurfaceMuted),

      // Label — buttons, tabs, chips.
      labelLarge: base(14, FontWeight.w600, 0.4, height: 1.3),
      labelMedium: base(12, FontWeight.w600, 0.5, height: 1.3),
      labelSmall: base(11, FontWeight.w600, 0.5, height: 1.3),
    );
  }
}
