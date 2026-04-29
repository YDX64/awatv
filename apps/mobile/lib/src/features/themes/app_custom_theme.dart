import 'dart:convert';

import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// Variants applied on top of the seed colour. The variant decides how
/// `ColorScheme.fromSeed` derives the rest of the palette and whether
/// the surface stack is overridden (OLED-true-black case) or left to
/// Material 3's tonal mapping.
enum ThemeVariant {
  /// Default Material 3 tonal scheme. Balanced contrast, matches
  /// Google's reference apps. The shipping default.
  standard,

  /// `DynamicSchemeVariant.vibrant` — pumps chroma so primary / secondary
  /// surfaces feel bolder. Right for users who want their accent colour
  /// to read as the hero of every screen.
  vibrant,

  /// `DynamicSchemeVariant.tonalSpot` — desaturated, calmer surfaces.
  /// Right for long viewing sessions where the UI should fade behind
  /// the content (the IPTV target use case).
  tonal,

  /// True-black variant for OLED displays. Surface and background are
  /// both forced to `#000000` so dark pixels physically turn off the
  /// panel — saves battery and gives the player chrome a "floats over
  /// the void" look. Only meaningful in dark mode; defaults back to
  /// [standard] when the active brightness is light.
  oledBlack,
}

extension ThemeVariantTr on ThemeVariant {
  /// Turkish display label. Used by the theme picker chips.
  String get tr => switch (this) {
        ThemeVariant.standard => 'Standart',
        ThemeVariant.vibrant => 'Canli',
        ThemeVariant.tonal => 'Yumusak',
        ThemeVariant.oledBlack => 'OLED siyah',
      };

  /// One-line subtitle shown under the variant chip when expanded.
  String get description => switch (this) {
        ThemeVariant.standard => 'Material 3 dengeli ton',
        ThemeVariant.vibrant => 'Daha doygun, dikkat cekici',
        ThemeVariant.tonal => 'Sakin, izleme dostu',
        ThemeVariant.oledBlack => 'Tam siyah, OLED tasarrufu',
      };

  /// Maps to a Flutter `DynamicSchemeVariant` for the seeded scheme.
  /// OLED variant rides on `expressive` for crisp accents that pop
  /// against the pure-black canvas; the canvas itself is forced after
  /// the scheme is generated.
  DynamicSchemeVariant get fromSeedVariant => switch (this) {
        ThemeVariant.standard => DynamicSchemeVariant.tonalSpot,
        ThemeVariant.vibrant => DynamicSchemeVariant.vibrant,
        ThemeVariant.tonal => DynamicSchemeVariant.neutral,
        ThemeVariant.oledBlack => DynamicSchemeVariant.expressive,
      };
}

/// Persisted theme customisation profile.
///
/// One Hive prefs key (`theme.custom`) carries the whole struct as JSON
/// so a single read on app boot is enough to restore the user's choice.
/// Defaults match the historical `BrandColors.primary` so users who
/// never open the theme screen keep the original look.
@immutable
class AppCustomTheme {
  const AppCustomTheme({
    this.seedColor = BrandColors.primary,
    this.variant = ThemeVariant.standard,
    this.useSystemAccent = false,
    this.cornerRadiusScale = 1.0,
  });

  /// Seed colour used by `ColorScheme.fromSeed` to derive the entire
  /// Material 3 palette. Constrained to opaque colours — alpha bits are
  /// stripped on `copyWith`.
  final Color seedColor;

  /// Tonal style applied to the seeded scheme.
  final ThemeVariant variant;

  /// When true, the OS accent colour (Android 12+ `dynamic_color`) is
  /// preferred over [seedColor] when one is available. Ignored on
  /// platforms that do not expose a system accent.
  final bool useSystemAccent;

  /// Multiplier applied to every `DesignTokens.radius*` value. Range
  /// 0.5–2.0; clamped at the screen layer before persistence.
  final double cornerRadiusScale;

  /// Default = the historic AWAtv look. Always safe to fall back to.
  static const AppCustomTheme defaults = AppCustomTheme();

  AppCustomTheme copyWith({
    Color? seedColor,
    ThemeVariant? variant,
    bool? useSystemAccent,
    double? cornerRadiusScale,
  }) {
    return AppCustomTheme(
      seedColor: seedColor ?? this.seedColor,
      variant: variant ?? this.variant,
      useSystemAccent: useSystemAccent ?? this.useSystemAccent,
      cornerRadiusScale: cornerRadiusScale ?? this.cornerRadiusScale,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        // ARGB int — round-trips through `Color(int)` cleanly. We strip
        // the alpha so a malformed save can't introduce a transparent
        // primary that vanishes from the chip palette.
        'seed': _argb32(seedColor),
        'variant': variant.name,
        'useSystemAccent': useSystemAccent,
        'cornerRadiusScale': cornerRadiusScale,
      };

  /// Pack a [Color] into a 32-bit ARGB int. Replaces the deprecated
  /// `.value` accessor; we rebuild the int from the per-channel
  /// `Color.r/g/b` doubles so future Flutter updates don't have to
  /// touch the persistence schema.
  static int _argb32(Color c) {
    final r = (c.r * 255).round() & 0xFF;
    final g = (c.g * 255).round() & 0xFF;
    final b = (c.b * 255).round() & 0xFF;
    return 0xFF000000 | (r << 16) | (g << 8) | b;
  }

  static AppCustomTheme fromJson(Map<String, dynamic> json) {
    final rawSeed = json['seed'];
    final seed = rawSeed is int
        ? Color(rawSeed & 0x00FFFFFF | 0xFF000000)
        : BrandColors.primary;
    final variantName = json['variant']?.toString();
    final variant = ThemeVariant.values.firstWhere(
      (ThemeVariant v) => v.name == variantName,
      orElse: () => ThemeVariant.standard,
    );
    final useSystem = json['useSystemAccent'] == true;
    final scaleRaw = json['cornerRadiusScale'];
    final scale = (scaleRaw is num ? scaleRaw.toDouble() : 1.0).clamp(
      0.5,
      2.0,
    );
    return AppCustomTheme(
      seedColor: seed,
      variant: variant,
      useSystemAccent: useSystem,
      cornerRadiusScale: scale,
    );
  }

  /// Encode for storage. Wraps [toJson] so callers don't need to know
  /// about the JSON envelope.
  String encode() => jsonEncode(toJson());

  /// Decode a previously-encoded payload. Returns [defaults] on any
  /// parse error so a corrupt save can never brick the app.
  ///
  /// Kept as a static method (rather than a named constructor) so the
  /// happy + fallback paths stay together in one place — a constructor
  /// can't return `defaults` on failure without throwing.
  // ignore: prefer_constructors_over_static_methods
  static AppCustomTheme decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final Object? parsed = jsonDecode(raw);
      if (parsed is! Map) return defaults;
      return fromJson(parsed.cast<String, dynamic>());
    } on Object {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppCustomTheme &&
        _argb32(other.seedColor) == _argb32(seedColor) &&
        other.variant == variant &&
        other.useSystemAccent == useSystemAccent &&
        other.cornerRadiusScale == cornerRadiusScale;
  }

  @override
  int get hashCode => Object.hash(
        _argb32(seedColor),
        variant,
        useSystemAccent,
        cornerRadiusScale,
      );
}

/// Curated accent colour swatches surfaced as preset chips. The full
/// list intentionally keeps eight strong, perceptually-distinct hues so
/// the picker always has at least one swatch matching the user's taste
/// without opening a generic colour wheel. The brand primary leads so
/// the default tile is always visible at the start of the row.
class ThemeAccentPresets {
  const ThemeAccentPresets._();

  /// Ordered by hue, brand first. Each entry pairs a Turkish label with
  /// an opaque ARGB seed value.
  static const List<ThemeAccentPreset> values = <ThemeAccentPreset>[
    ThemeAccentPreset(
      label: 'Marka',
      color: BrandColors.primary,
    ),
    ThemeAccentPreset(label: 'Indigo', color: Color(0xFF4F46E5)),
    ThemeAccentPreset(label: 'Cyan', color: Color(0xFF06B6D4)),
    ThemeAccentPreset(label: 'Magenta', color: Color(0xFFD946EF)),
    ThemeAccentPreset(label: 'Turuncu', color: Color(0xFFF97316)),
    ThemeAccentPreset(label: 'Yesil', color: Color(0xFF22C55E)),
    ThemeAccentPreset(label: 'Kirmizi', color: Color(0xFFEF4444)),
    ThemeAccentPreset(label: 'Altin', color: Color(0xFFEAB308)),
    ThemeAccentPreset(label: 'Lacivert', color: Color(0xFF334155)),
  ];
}

/// Single accent preset surfaced in the chip row. Plain data class so
/// the picker can render it without loading an extra package.
@immutable
class ThemeAccentPreset {
  const ThemeAccentPreset({required this.label, required this.color});

  final String label;
  final Color color;
}
