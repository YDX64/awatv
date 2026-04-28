import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hive prefs key for the persisted backend preference.
const String kPlayerBackendPreferenceKey = 'player.backend.preference';

/// Tri-state preference for which playback engine to use.
///
/// Persisted to the shared `prefs` Hive box on every change so the
/// choice survives app restarts. Reads on first access return whatever
/// the user last picked, defaulting to [PlayerBackend.auto] when the
/// key is missing.
class PlayerBackendPreferenceNotifier extends StateNotifier<PlayerBackend> {
  PlayerBackendPreferenceNotifier(this._ref)
      : super(_loadInitial(_ref));

  final Ref _ref;

  static PlayerBackend _loadInitial(Ref ref) {
    try {
      final box = ref.read(awatvStorageProvider).prefsBox;
      final raw = box.get(kPlayerBackendPreferenceKey);
      if (raw is String) {
        return PlayerBackend.values.firstWhere(
          (PlayerBackend b) => b.name == raw,
          orElse: () => PlayerBackend.auto,
        );
      }
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('PlayerBackendPreferenceNotifier load failed: $e');
      }
    }
    return PlayerBackend.auto;
  }

  /// Updates the preference and writes it through to Hive. The Hive
  /// write is fire-and-forget — the in-memory state flips immediately
  /// so consumers re-render without waiting on disk I/O.
  Future<void> set(PlayerBackend next) async {
    state = next;
    try {
      final box = _ref.read(awatvStorageProvider).prefsBox;
      await box.put(kPlayerBackendPreferenceKey, next.name);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('PlayerBackendPreferenceNotifier save failed: $e');
      }
    }
  }
}

/// Riverpod state provider for the player backend preference.
///
/// `keepAlive` is implicit — `StateNotifierProvider` is shared by
/// default, and the underlying notifier is dirt-cheap to keep around.
/// Watch this from the player screen / settings sheet to react to
/// preference changes.
final StateNotifierProvider<PlayerBackendPreferenceNotifier, PlayerBackend>
    playerBackendPreferenceProvider =
    StateNotifierProvider<PlayerBackendPreferenceNotifier, PlayerBackend>(
  (Ref ref) => PlayerBackendPreferenceNotifier(ref),
);
