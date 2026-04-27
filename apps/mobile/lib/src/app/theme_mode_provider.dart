import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_mode_provider.g.dart';

/// Persisted app theme mode — `system` by default. Stored under a single
/// shared-preferences key so we can read it synchronously after init.
@Riverpod(keepAlive: true)
class AppThemeMode extends _$AppThemeMode {
  static const String _prefsKey = 'awatv.themeMode';

  @override
  ThemeMode build() {
    // Synchronous read via SharedPreferencesAsync would force the entire
    // `MaterialApp` to wait — so we expose `system` immediately and let
    // hydration happen as a side-effect when the value differs.
    _hydrate();
    return ThemeMode.system;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored == null) return;
    final mode = ThemeMode.values.firstWhere(
      (m) => m.name == stored,
      orElse: () => ThemeMode.system,
    );
    if (mode != state) state = mode;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  Future<void> toggle() async {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.light => ThemeMode.system,
    };
    await setMode(next);
  }
}
