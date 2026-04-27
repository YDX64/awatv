import 'package:awatv_ui/src/theme/brand_colors.dart';
import 'package:awatv_ui/src/theme/typography.dart';
import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Builds the `ThemeData` for the AWAtv shell.
///
/// One seed colour drives the entire Material 3 colour scheme; the rest
/// of the theme is then tuned to match the dark-first, glass-flavoured
/// aesthetic described in `docs/DESIGN.md`.
class AppTheme {
  const AppTheme._();

  /// Dark theme — the default shipping theme.
  static ThemeData dark() => _build(Brightness.dark);

  /// Light theme — high-contrast, content-first.
  static ThemeData light() => _build(Brightness.light);

  // -------------------------------------------------------------------------
  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.primary,
      brightness: brightness,
      primary: BrandColors.primary,
      secondary: BrandColors.secondary,
      error: BrandColors.error,
      surface: isDark ? BrandColors.surface : BrandColors.lightSurface,
      onSurface:
          isDark ? BrandColors.onSurface : BrandColors.onLightSurface,
      surfaceContainerHighest:
          isDark ? BrandColors.surfaceHigh : BrandColors.lightSurfaceHigh,
      outline: isDark ? BrandColors.outline : BrandColors.lightOutline,
    );

    final TextTheme textTheme = AppTypography.textTheme(scheme);

    final Color scaffoldBackground =
        isDark ? BrandColors.background : BrandColors.lightBackground;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: scaffoldBackground,
      canvasColor: scaffoldBackground,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,

      // App bar — transparent so the BlurAppBar can layer a backdrop.
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      // Cards — soft, rounded, low elevation. Pair with custom widgets
      // for hero treatments.
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: DesignTokens.elevationMid,
        shadowColor: Colors.black.withValues(alpha: 0.45),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        ),
      ),

      // Filled buttons — primary CTA shape.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(DesignTokens.minTapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceL,
            vertical: DesignTokens.spaceM,
          ),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          ),
        ),
      ),

      // Outlined — secondary actions inside cards.
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
            borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          ),
        ),
      ),

      // Text — tertiary actions, links.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceM,
            vertical: DesignTokens.spaceS,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          ),
        ),
      ),

      // Icon buttons — generous tap targets, brand splash on press.
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(DesignTokens.minTapTarget),
          foregroundColor: scheme.onSurface,
          highlightColor: scheme.primary.withValues(alpha: 0.12),
        ),
      ),

      // Chips — used on genre / filter rows.
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
          borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
        ),
        showCheckmark: false,
      ),

      // Inputs — pill-rounded fields.
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
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),

      // Bottom navigation — selected pill on brand primary.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? BrandColors.surface.withValues(alpha: 0.85)
            : BrandColors.lightSurface.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurface,
            size: 24,
          );
        }),
        labelTextStyle:
            WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          final bool selected = states.contains(WidgetState.selected);
          return (textTheme.labelMedium ?? const TextStyle()).copyWith(
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.75),
          );
        }),
        elevation: 0,
        height: 68,
      ),

      // Bottom sheets — high surface, big rounding at the top.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? BrandColors.surfaceHigh
            : BrandColors.lightSurfaceHigh,
        modalBackgroundColor: isDark
            ? BrandColors.surfaceHigh
            : BrandColors.lightSurfaceHigh,
        showDragHandle: true,
        elevation: DesignTokens.elevationHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DesignTokens.radiusXL),
          ),
        ),
      ),

      // Dialogs — match the modal sheet look.
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? BrandColors.surfaceHigh
            : BrandColors.lightSurfaceHigh,
        elevation: DesignTokens.elevationHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      // Snackbars — floating pill at the bottom.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? BrandColors.surfaceHigh
            : BrandColors.lightSurfaceHigh,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        ),
        elevation: DesignTokens.elevationMid,
      ),

      // Dividers — barely there.
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.35),
        thickness: 1,
        space: 1,
      ),

      // Progress indicators — brand primary.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),

      // Sliders — brand primary, generous track.
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.18),
        trackHeight: 4,
      ),

      // List tiles — used inside settings.
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
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        ),
      ),

      // Tooltips — lightweight glass.
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        ),
        textStyle: textTheme.labelSmall,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceS,
          vertical: DesignTokens.spaceXs,
        ),
      ),

      // Page transition — fade + lift, customised per route via FadeRoute.
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
