import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:awatv_mobile/src/shared/background_playback/awa_audio_handler.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'background_playback_controller.g.dart';

/// Hive prefs key for the persisted "background playback enabled" toggle.
const String kBackgroundPlaybackPrefKey = 'bg.playback.enabled';

/// User toggle for keeping audio + video alive when the app moves off-
/// screen.
///
/// The state is just a [bool], persisted to the shared `prefs` Hive box.
/// The premium gate is checked at the call-site — this notifier itself
/// is happy to flip on or off regardless, so a freshly-promoted user's
/// previously-stored preference takes effect immediately.
@Riverpod(keepAlive: true)
class BackgroundPlayback extends _$BackgroundPlayback {
  @override
  bool build() {
    try {
      final box = ref.read(awatvStorageProvider).prefsBox;
      final raw = box.get(kBackgroundPlaybackPrefKey);
      if (raw is bool) return raw;
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('BackgroundPlayback load failed: $e');
      }
    }
    return false;
  }

  /// Updates the toggle and persists it. Fire-and-forget on the I/O so
  /// consumers re-render immediately.
  Future<void> setEnabled(bool value) async {
    state = value;
    try {
      final box = ref.read(awatvStorageProvider).prefsBox;
      await box.put(kBackgroundPlaybackPrefKey, value);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('BackgroundPlayback save failed: $e');
      }
    }
  }
}

/// Singleton [AwaAudioHandler]. Initialised exactly once per process by
/// [ensureAudioServiceInitialized] and re-used for the lifetime of the
/// app — registering twice with `AudioService.init` throws.
AwaAudioHandler? _handler;

/// Riverpod handle for the audio handler. Returns null until
/// [ensureAudioServiceInitialized] has finished — callers should treat
/// null as "no media-session integration available on this platform".
@Riverpod(keepAlive: true)
AwaAudioHandler? audioHandler(Ref ref) => _handler;

/// Boots the OS-level media session. Idempotent and safe to call from
/// `main()`; subsequent calls return the same handler instance.
///
/// Web is intentionally skipped — `audio_service` has only partial web
/// support (no MediaSession API on every browser, and no `dart:isolate`
/// for the background isolate path). On web the player still works,
/// it just doesn't show a lock-screen tile.
Future<AwaAudioHandler?> ensureAudioServiceInitialized() async {
  if (kIsWeb) return null;
  if (_handler != null) return _handler;
  try {
    _handler = await AudioService.init<AwaAudioHandler>(
      builder: AwaAudioHandler.new,
      config: const AudioServiceConfig(
        // Android notification channel — must match the manifest service
        // declaration so the foreground notification actually attaches.
        androidNotificationChannelId: 'tv.awatv.mobile.channel.audio',
        androidNotificationChannelName: 'AWAtv Oynatma',
        androidNotificationChannelDescription:
            'Arkaplanda yayın oynatılırken görünür.',
        androidNotificationOngoing: true,
      ),
    );
  } on Object catch (e) {
    if (kDebugMode) {
      debugPrint('ensureAudioServiceInitialized failed: $e');
    }
    _handler = null;
  }
  return _handler;
}
