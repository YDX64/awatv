import 'dart:convert';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hive metadata key for subtitle settings — matches the AsyncStorage
/// key Streas RN uses (`awatv_subtitle_settings`) so a future
/// cross-platform export/import is bytes-for-bytes compatible.
const String kSubtitleSettingsKey = 'awatv_subtitle_settings';

/// Controller for the user-configurable subtitle rendering settings.
///
/// Persists changes to Hive's metadata box (no TTL) on every write and
/// hydrates from disk on first read. UI screens read via:
///
/// ```dart
/// final settings = ref.watch(subtitleSettingsControllerProvider);
/// ref.read(subtitleSettingsControllerProvider.notifier).setSize(...);
/// ```
class SubtitleSettingsController
    extends StateNotifier<SubtitleSettings> {
  SubtitleSettingsController({required AwatvStorage storage})
      : _storage = storage,
        super(const SubtitleSettings()) {
    _hydrate();
  }

  final AwatvStorage _storage;

  Future<void> _hydrate() async {
    try {
      // We use a 365-day TTL so settings are effectively permanent —
      // reusing the metadata box keeps the public API of [AwatvStorage]
      // unchanged. A dedicated prefs box would also work but adds
      // initialisation complexity for what is a single value.
      final raw = await _storage.getMetadataJson(
        kSubtitleSettingsKey,
        ttl: const Duration(days: 365),
      );
      if (raw == null) return;
      state = SubtitleSettings.fromJson(raw);
    } on Object {
      // Best-effort hydration — corrupt JSON simply falls back to the
      // baked-in defaults so the user still gets a usable picker.
    }
  }

  Future<void> _persist(SubtitleSettings next) async {
    state = next;
    try {
      await _storage.putMetadataJson(
        kSubtitleSettingsKey,
        jsonDecode(jsonEncode(next.toJson())) as Map<String, dynamic>,
      );
    } on Object {
      // Persistence failures don't roll back state — the user still
      // wants to see their just-applied change. Next launch will
      // simply use defaults.
    }
  }

  // -- Top-level toggles ---------------------------------------------------

  Future<void> setEnabled({required bool value}) =>
      _persist(state.copyWith(enabled: value));

  Future<void> setPreferredLanguage(String code) =>
      _persist(state.copyWith(preferredLanguage: code));

  Future<void> setSize(SubtitleSize size) =>
      _persist(state.copyWith(size: size));

  Future<void> setColor(SubtitleColor color) =>
      _persist(state.copyWith(color: color));

  Future<void> setBackground(SubtitleBackground bg) =>
      _persist(state.copyWith(background: bg));

  Future<void> setPosition(SubtitlePosition pos) =>
      _persist(state.copyWith(position: pos));

  Future<void> setBold({required bool value}) =>
      _persist(state.copyWith(bold: value));

  Future<void> setApiKey(String? value) =>
      _persist(state.copyWith(apiKey: value));

  /// Marks an SRT as currently loaded — surfaced in the picker as
  /// "Yuklenen altyazi: filename".
  Future<void> markLoaded({
    required String fileName,
    required String label,
  }) =>
      _persist(
        state.copyWith(
          loadedFileName: fileName,
          loadedLabel: label,
          enabled: true,
        ),
      );

  /// Clears the loaded SRT pointer (the user disabled subtitles or
  /// switched to a different track).
  Future<void> clearLoaded() => _persist(
        state.copyWith(
          clearLoadedFileName: true,
          clearLoadedLabel: true,
        ),
      );

  /// Bulk update — used by the "Kaydet ve uygula" button on the picker
  /// settings sheet. Applies a draft `SubtitleSettings` in one write.
  Future<void> apply(SubtitleSettings next) => _persist(next);
}

/// Riverpod handle for [SubtitleSettingsController]. Kept alive so the
/// hydrated state survives navigation between the player and the picker.
final subtitleSettingsControllerProvider = StateNotifierProvider<
    SubtitleSettingsController, SubtitleSettings>((Ref ref) {
  return SubtitleSettingsController(
    storage: ref.watch(awatvStorageProvider),
  );
});
