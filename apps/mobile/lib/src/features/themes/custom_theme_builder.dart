import 'package:awatv_mobile/src/features/themes/app_custom_theme.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Converts an [AppCustomTheme] + [Brightness] pair into a fully-styled
/// `ThemeData` instance.
///
/// Mirrors the structure of `AppTheme._build` in the awatv_ui package
/// but parameterises the seed colour, scheme variant and corner-radius
/// scale. Component themes (chips, inputs, sliders, etc.) are
/// regenerated from the new scheme so the entire surface stack feels
/// cohesive — flipping the seed to magenta correctly tints navigation
/// rail, dialog accents, slider tracks, and so on without any extra
/// per-screen wiring.
///
/// OLED variant override:
///   * In dark mode, `surface`, `background` and `surfaceContainerHighest`
///     are slammed to true black so the player chrome (and the body
///     scaffold) physically turns OLED pixels off. Cards keep a +5
///     lightness lift so they remain visually distinct from the canvas.
///   * In light mode, OLED is meaningless — we silently fall back to
///     the [ThemeVariant.standard] palette so the picker preview is
///     still useful while the system is forced light.
class CustomThemeBuilder {
  const CustomThemeBuilder._();

  /// Resolve the seeded scheme + scaled radii into a `ThemeData`.
  static ThemeData build(AppCustomTheme custom, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final isOled = custom.variant == ThemeVariant.oledBlack && isDark;

    // Seeded scheme — Material 3's algorithm derives the entire palette
    // from a single colour + variant. We override surface/background
    // explicitly so the AWAtv aurora canvas stays distinct from the
    // default Material surfaces (which lean a touch warmer).
    final seedScheme = ColorScheme.fromSeed(
      seedColor: custom.seedColor,
      brightness: brightness,
      dynamicSchemeVariant: custom.variant.fromSeedVariant,
    );

    // Surface stack — three layers of brightness so cards / sheets /
    // dialogs all read as distinct elevations. OLED collapses the
    // bottom two to pure black so dark pixels turn off.
    final Color background;
    final Color surface;
    final Color surfaceHigh;
    final Color outline;

    if (isOled) {
      background = Colors.black;
      surface = Colors.black;
      // Cards / list rows still need to read as separate from the
      // canvas, so we lift the higher surface a hair. 12% white on
      // pure black is the lowest contrast that survives the AMOLED
      // smearing without crushing.
      surfaceHigh = const Color(0xFF101010);
      outline = const Color(0xFF222222);
    } else if (isDark) {
      background = BrandColors.background;
      surface = BrandColors.surface;
      surfaceHigh = BrandColors.surfaceHigh;
      outline = BrandColors.outline;
    } else {
      background = BrandColors.lightBackground;
      surface = BrandColors.lightSurface;
      surfaceHigh = BrandColors.lightSurfaceHigh;
      outline = BrandColors.lightOutline;
    }

    final scheme = seedScheme.copyWith(
      surface: surface,
      surfaceContainerHighest: surfaceHigh,
      outline: outline,
      // Keep error / success in the AWAtv brand register — Material 3's
      // default error red leans pink, which clashes with the live-pulse
      // accent we use elsewhere.
      error: BrandColors.error,
    );

    final textTheme = AppTypography.textTheme(scheme);

    // Scaled radii — every named token gets multiplied by the user's
    // chosen factor. We clamp the input to [0.5..2.0] in case a stale
    // payload from a future build sneaks through the JSON decoder.
    final scale = custom.cornerRadiusScale.clamp(0.5, 2.0);
    final radiusS = DesignTokens.radiusS * scale;
    final radiusM = DesignTokens.radiusM * scale;
    final radiusL = DesignTokens.radiusL * scale;
    final radiusXL = DesignTokens.radiusXL * scale;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: DesignTokens.elevationMid,
        shadowColor: Colors.black.withValues(alpha: 0.45),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusL),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(DesignTokens.minTapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceL,
            vertical: DesignTokens.spaceM,
          ),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusL),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(DesignTokens.minTapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceL,
            vertical: DesignTokens.spaceM,
          ),
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusL),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceM,
            vertical: DesignTokens.spaceS,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusM),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(DesignTokens.minTapTarget),
          foregroundColor: scheme.onSurface,
          highlightColor: scheme.primary.withValues(alpha: 0.12),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primary,
        secondarySelectedColor: scheme.primary,
        disabledColor: scheme.surface,
        labelStyle: textTheme.labelMedium ?? const TextStyle(),
        secondaryLabelStyle:
            (textTheme.labelMedium ?? const TextStyle()).copyWith(
          color: scheme.onPrimary,
        ),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceM,
          vertical: DesignTokens.spaceXs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXL),
        ),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceM,
          vertical: DesignTokens.spaceM,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.5),
        ),
        labelStyle: textTheme.labelLarge,
        floatingLabelStyle: textTheme.labelLarge?.copyWith(
          color: scheme.primary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusL),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusL),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusL),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusL),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? surface.withValues(alpha: 0.85)
            : surface.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurface,
            size: 24,
          );
        }),
        labelTextStyle:
            WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          final selected = states.contains(WidgetState.selected);
          return (textTheme.labelMedium ?? const TextStyle()).copyWith(
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.75),
          );
        }),
        elevation: 0,
        height: 68,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceHigh,
        modalBackgroundColor: surfaceHigh,
        showDragHandle: true,
        elevation: DesignTokens.elevationHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusXL),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceHigh,
        elevation: DesignTokens.elevationHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXL),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHigh,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusM),
        ),
        elevation: DesignTokens.elevationMid,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.35),
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.18),
        trackHeight: 4,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurface,
        textColor: scheme.onSurface,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceM,
          vertical: DesignTokens.spaceXs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusM),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(radiusS),
        ),
        textStyle: textTheme.labelSmall,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceS,
          vertical: DesignTokens.spaceXs,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
