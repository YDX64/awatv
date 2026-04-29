// Pure unit tests for the [AppCustomTheme] data class. Verifies the
// JSON encode/decode round-trip, equality semantics, and the boundary
// clamps (seed alpha forced opaque, radius scale clamped 0.5–2.0).

import 'package:awatv_mobile/src/features/themes/app_custom_theme.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaults', () {
    test('match the historical AWAtv brand', () {
      const t = AppCustomTheme.defaults;
      expect(t.seedColor, BrandColors.primary);
      expect(t.variant, ThemeVariant.standard);
      expect(t.useSystemAccent, isFalse);
      expect(t.cornerRadiusScale, 1.0);
    });
  });

  group('copyWith', () {
    test('keeps untouched fields', () {
      const t = AppCustomTheme.defaults;
      final next = t.copyWith(variant: ThemeVariant.vibrant);
      expect(next.seedColor, t.seedColor);
      expect(next.variant, ThemeVariant.vibrant);
      expect(next.cornerRadiusScale, t.cornerRadiusScale);
    });

    test('replaces the seed color', () {
      const t = AppCustomTheme.defaults;
      final next = t.copyWith(seedColor: const Color(0xFF112233));
      // Round-trip through JSON to read the packed seed RGB.
      final encoded = next.toJson();
      expect(encoded['seed'], 0xFF112233);
    });
  });

  group('JSON', () {
    test('round-trips through encode/decode', () {
      const original = AppCustomTheme(
        seedColor: Color(0xFF4F46E5),
        variant: ThemeVariant.vibrant,
        useSystemAccent: true,
        cornerRadiusScale: 1.5,
      );
      final encoded = original.encode();
      final decoded = AppCustomTheme.decode(encoded);
      expect(decoded, original);
    });

    test('decode returns defaults for null', () {
      expect(AppCustomTheme.decode(null), AppCustomTheme.defaults);
    });

    test('decode returns defaults for empty string', () {
      expect(AppCustomTheme.decode(''), AppCustomTheme.defaults);
    });

    test('decode returns defaults for malformed JSON', () {
      expect(AppCustomTheme.decode('not-json'), AppCustomTheme.defaults);
      expect(AppCustomTheme.decode('"a-string"'), AppCustomTheme.defaults);
      expect(AppCustomTheme.decode('[1,2,3]'), AppCustomTheme.defaults);
    });

    test('decode clamps cornerRadiusScale outside 0.5..2.0', () {
      const high = AppCustomTheme(cornerRadiusScale: 5);
      final decoded = AppCustomTheme.decode(high.encode());
      expect(decoded.cornerRadiusScale, 2.0);

      const low = AppCustomTheme(cornerRadiusScale: 0.1);
      final decodedLow = AppCustomTheme.decode(low.encode());
      expect(decodedLow.cornerRadiusScale, 0.5);
    });

    test('decode falls back to standard variant for unknown name', () {
      // Fake a payload with an unknown variant.
      const payload =
          '{"seed":4283215075,"variant":"unknown","useSystemAccent":false,"cornerRadiusScale":1.0}';
      final decoded = AppCustomTheme.decode(payload);
      expect(decoded.variant, ThemeVariant.standard);
    });

    test('seed alpha is forced opaque on decode', () {
      // Encode a transparent seed, expect it to come back opaque.
      const transparent = AppCustomTheme(seedColor: Color(0x00FF0000));
      final raw = transparent.encode();
      final decoded = AppCustomTheme.decode(raw);
      // Alpha bits should always be 0xFF — read via toJson which packs
      // the channels back into a 32-bit int.
      final argb = decoded.toJson()['seed'] as int;
      expect((argb >> 24) & 0xFF, 0xFF);
    });
  });

  group('equality', () {
    test('two defaults are equal', () {
      expect(AppCustomTheme.defaults, AppCustomTheme.defaults);
    });

    test('different seed produces different theme', () {
      const a = AppCustomTheme(seedColor: Color(0xFFFF0000));
      const b = AppCustomTheme(seedColor: Color(0xFF00FF00));
      expect(a, isNot(equals(b)));
    });

    test('different variant produces different theme', () {
      const a = AppCustomTheme();
      const b = AppCustomTheme(variant: ThemeVariant.vibrant);
      expect(a, isNot(equals(b)));
    });

    test('different scale produces different theme', () {
      const a = AppCustomTheme();
      const b = AppCustomTheme(cornerRadiusScale: 1.5);
      expect(a, isNot(equals(b)));
    });

    test('hashCode aligns with equality', () {
      const a = AppCustomTheme(seedColor: Color(0xFF4F46E5));
      const b = AppCustomTheme(seedColor: Color(0xFF4F46E5));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ThemeVariant', () {
    test('every variant has a Turkish label', () {
      for (final v in ThemeVariant.values) {
        expect(v.tr, isNotEmpty);
      }
    });

    test('every variant has a description', () {
      for (final v in ThemeVariant.values) {
        expect(v.description, isNotEmpty);
      }
    });

    test('fromSeedVariant returns a non-null DynamicSchemeVariant', () {
      for (final v in ThemeVariant.values) {
        // Each variant must map to a real Material scheme variant.
        expect(v.fromSeedVariant, isNotNull);
      }
    });

    test('OLED variant maps to expressive scheme', () {
      expect(ThemeVariant.oledBlack.fromSeedVariant,
          DynamicSchemeVariant.expressive);
    });
  });

  group('ThemeAccentPresets', () {
    test('contains at least one preset', () {
      expect(ThemeAccentPresets.values, isNotEmpty);
    });

    test('every preset has a non-empty label', () {
      for (final p in ThemeAccentPresets.values) {
        expect(p.label, isNotEmpty);
      }
    });

    test('first preset is the brand colour', () {
      // Compare via the encoded ARGB int — the public toARGB32 helper
      // is private to AppCustomTheme. Using equality on Color is safe
      // because both colours are const-built at compile time.
      expect(
        ThemeAccentPresets.values.first.color,
        BrandColors.primary,
      );
    });
  });
}
