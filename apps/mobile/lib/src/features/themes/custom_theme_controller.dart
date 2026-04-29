import 'package:awatv_mobile/src/features/themes/app_custom_theme.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'custom_theme_controller.g.dart';

/// Persisted custom theme controller.
///
/// Mirrors the `AppThemeMode` controller: returns [AppCustomTheme.defaults]
/// synchronously so `MaterialApp.router` can build immediately, then
/// hydrates from `SharedPreferences` and pushes the persisted value once
/// it is ready. The Hive prefs key is `theme.custom`.
///
/// A small in-memory "preview" override exists on top of the persisted
/// state so the theme picker can surface a 5-second "Test et" view
/// without writing the value to disk. When the preview window closes
/// (either timeout or explicit cancel) the visible theme reverts to
/// whatever is persisted.
@Riverpod(keepAlive: true)
class CustomThemeController extends _$CustomThemeController {
  static const String _prefsKey = 'theme.custom';

  /// In-memory override that shadows [_persisted] while a preview is
  /// active. The notifier exposes only the "effective" theme via
  /// [state]; consumers therefore never need to know about the preview
  /// machinery directly.
  AppCustomTheme? _preview;

  /// Last known persisted value — kept so we can revert from a preview
  /// without re-reading shared preferences.
  AppCustomTheme _persisted = AppCustomTheme.defaults;

  @override
  AppCustomTheme build() {
    _hydrate();
    return AppCustomTheme.defaults;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final restored = AppCustomTheme.decode(raw);
    _persisted = restored;
    if (_preview == null && state != restored) state = restored;
  }

  /// Persist the new theme. Cancels any running preview so the saved
  /// value becomes immediately visible.
  Future<void> save(AppCustomTheme theme) async {
    _persisted = theme;
    _preview = null;
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, theme.encode());
  }

  /// Reset to the historical AWAtv default and clear the persisted
  /// payload. Used by the "Sifirla" button on the picker.
  Future<void> reset() async {
    _preview = null;
    _persisted = AppCustomTheme.defaults;
    state = AppCustomTheme.defaults;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Apply [candidate] as a transient preview. The state flips to the
  /// candidate immediately and reverts on [endPreview]. Persistence is
  /// untouched — refreshing the app while a preview is up returns to
  /// the saved theme on next launch.
  void preview(AppCustomTheme candidate) {
    _preview = candidate;
    state = candidate;
  }

  /// Drop any active preview and revert to the persisted theme. Safe
  /// to call repeatedly.
  void endPreview() {
    if (_preview == null) return;
    _preview = null;
    state = _persisted;
  }

  /// True while a preview is overriding the persisted state.
  bool get hasPreview => _preview != null;

  /// The persisted value (independent of any active preview). Used by
  /// the picker UI so it can render the saved selection while the
  /// preview is showing a different combination.
  AppCustomTheme get persisted => _persisted;
}
