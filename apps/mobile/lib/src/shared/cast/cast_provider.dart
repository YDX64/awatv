import 'dart:async';

import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cast_provider.g.dart';

/// Single shared [CastEngine] instance for the running app.
///
/// `keepAlive: true` because the engine owns native resources that are
/// expensive to spin up — discovery handles, route observers, and event
/// channel subscriptions. Tearing it down on every screen rebuild would
/// flicker the system AirPlay picker on iOS.
///
/// Disposed only when the provider container itself shuts down (i.e.
/// app exit) — Riverpod calls [CastEngine.dispose] via [Ref.onDispose].
@Riverpod(keepAlive: true)
CastEngine castEngine(Ref ref) {
  final engine = CastEngine.platform();
  ref.onDispose(() async {
    await engine.dispose();
  });
  return engine;
}

/// Live cast-session state stream as a Riverpod async snapshot.
///
/// Every consumer of `ref.watch(castSessionStreamProvider)` rebuilds on
/// every emission; that's fine for the picker sheet which is short-lived
/// and the cast button which paints a small icon. Heavier widgets should
/// use the [castControllerProvider] directly and select on individual
/// fields.
@Riverpod(keepAlive: true)
Stream<CastSession> castSessionStream(Ref ref) {
  final engine = ref.watch(castEngineProvider);
  return engine.sessions();
}

/// Convenience selector — true when a cast session is currently active
/// (connecting or connected). Used by the player screen to mirror local
/// playback to the receiver and dim local controls accordingly.
@Riverpod(keepAlive: true)
bool castIsActive(Ref ref) {
  final session = ref.watch(castSessionStreamProvider);
  return session.maybeWhen(
    data: (CastSession s) => s is CastConnecting || s is CastConnected,
    orElse: () => false,
  );
}

/// Convenience selector — the connected device's display name, or null.
@Riverpod(keepAlive: true)
String? castConnectedDeviceName(Ref ref) {
  final session = ref.watch(castSessionStreamProvider);
  return session.maybeWhen(
    data: (CastSession s) => s is CastConnected ? s.target.name : null,
    orElse: () => null,
  );
}

/// Imperative facade for the cast engine.
///
/// Lives next to the player screen — the screen reads it via
/// `ref.read(castControllerProvider)` to fire discovery, mirror
/// playback, and tear sessions down. State is exposed via the parent
/// [castSessionStreamProvider]; this controller is intentionally
/// stateless.
class CastController {
  CastController(this._ref);

  final Ref _ref;

  CastEngine get _engine => _ref.read(castEngineProvider);

  /// Begins discovery. Idempotent — calling while already discovering
  /// is a no-op at the engine level.
  Future<void> discover() async {
    try {
      await _engine.startDiscovery();
    } on CastUnsupportedException catch (e) {
      if (kDebugMode) debugPrint('cast.discover unsupported: $e');
      // Engine emits a CastError on the stream; consumers handle it via
      // the picker UI.
    } on Object catch (e) {
      if (kDebugMode) debugPrint('cast.discover failed: $e');
    }
  }

  /// Stops discovery. Safe to call regardless of state.
  Future<void> stopDiscovery() async {
    await _engine.stopDiscovery();
  }

  /// Connects to [device]. The picker UI watches the session stream for
  /// the resulting state transition.
  Future<void> connect(CastDevice device) async {
    try {
      await _engine.connect(device);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('cast.connect failed: $e');
      // Engine has already emitted CastError; nothing else to do here.
    }
  }

  /// On iOS, surfaces the system-native AirPlay picker. On other
  /// platforms this is a no-op (the picker UI is purely Flutter-side
  /// for Chromecast).
  Future<void> showAirPlayPicker() async {
    final engine = _engine;
    if (engine is AirPlayEngine) {
      try {
        await engine.showRoutePicker();
      } on CastUnsupportedException catch (e) {
        if (kDebugMode) debugPrint('cast.airplay picker unsupported: $e');
      }
    }
  }

  /// Mirrors [source] onto the active receiver session. Wraps the URL
  /// through [proxify] so private-LAN / mixed-content panels still work
  /// when the receiver is on a foreign network or running on a receiver
  /// app that enforces HTTPS.
  ///
  /// Pauses the local controller before handing off so two audio
  /// outputs don't race.
  Future<void> mirror(
    MediaSource source, {
    required AwaPlayerController localController,
    String? title,
    String? subtitle,
    String? artworkUrl,
    bool isLive = false,
  }) async {
    final session = _engine.currentSession;
    if (session is! CastConnected) {
      throw const CastNotConnectedException();
    }

    // Capture the local position so VOD can pick up where it left off
    // on the receiver. For live we always start at zero — receivers
    // ignore startPosition for live anyway.
    var startPosition = Duration.zero;
    if (!isLive) {
      try {
        // The local controller exposes positions via a stream. Read the
        // very next value with a short timeout so a stalled stream
        // doesn't block the cast handoff.
        startPosition = await localController.positions.first.timeout(
          const Duration(milliseconds: 250),
          onTimeout: () => Duration.zero,
        );
      } on Object {
        startPosition = Duration.zero;
      }
    }

    // Pause local playback so we don't double-decode while the cast
    // session takes over.
    try {
      await localController.pause();
    } on Object {
      // Best-effort.
    }

    final media = CastMedia(
      url: proxify(source.url),
      title: title ?? source.title,
      subtitle: subtitle,
      artworkUrl: artworkUrl,
      headers: source.headers,
      contentType: _inferContentType(source),
      streamType: isLive ? CastStreamType.live : CastStreamType.buffered,
      startPosition: startPosition,
    );

    await _engine.loadMedia(media);
  }

  /// Resumes local playback at the receiver's last-known position and
  /// disconnects the cast session. Used when the user taps "Bağlantıyı kes".
  Future<void> unmirror({
    required AwaPlayerController localController,
    bool resumeLocal = true,
  }) async {
    Duration? resumeAt;
    final session = _engine.currentSession;
    if (resumeLocal && session is CastConnected) {
      resumeAt = session.state.position;
    }

    await _engine.disconnect();

    if (resumeLocal && resumeAt != null && resumeAt > Duration.zero) {
      try {
        await localController.seek(resumeAt);
        await localController.play();
      } on Object {
        // Best-effort — local controller may have moved on.
      }
    }
  }

  /// Routes a play/pause through the active receiver. Intended for the
  /// player controls layer when the cast session is active.
  Future<void> togglePlayPause() async {
    final session = _engine.currentSession;
    if (session is! CastConnected) return;
    if (session.state.playing) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
  }

  /// Routes a seek to the active receiver.
  Future<void> seek(Duration to) async {
    if (_engine.currentSession is! CastConnected) return;
    await _engine.seek(to);
  }

  /// Routes a volume change to the active receiver. Volume is on a 0..1
  /// scale to match `CastEngine.setVolume`.
  Future<void> setVolume(double volume) async {
    if (_engine.currentSession is! CastConnected) return;
    await _engine.setVolume(volume);
  }

  /// Best-effort MIME inference, mirroring [CastMedia.resolvedContentType]
  /// but with the option to detect Xtream-Codes URLs that lack an
  /// extension entirely (e.g. `/live/user/pass/12345`).
  String? _inferContentType(MediaSource source) {
    final url = source.url.toLowerCase();
    if (url.contains('.m3u8')) return 'application/vnd.apple.mpegurl';
    if (url.contains('.mpd')) return 'application/dash+xml';
    if (url.contains('.mp4')) return 'video/mp4';
    if (url.contains('.mkv')) return 'video/x-matroska';
    if (url.contains('.ts')) return 'video/mp2t';
    // Xtream live with no extension: most receivers treat raw TS okay,
    // and Chromecast happily plays HLS pointed at /live/.../index.m3u8.
    if (url.contains('/live/')) return 'video/mp2t';
    return null;
  }
}

/// Cast controller — one instance shared across the app.
///
/// Stateless coordinator over [castEngineProvider]; consumers read
/// imperatively via `ref.read(castControllerProvider)`. State updates
/// arrive via [castSessionStreamProvider].
@Riverpod(keepAlive: true)
CastController castController(Ref ref) {
  return CastController(ref);
}
