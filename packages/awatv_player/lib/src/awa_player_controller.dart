import 'package:awatv_player/src/backends/media_kit_backend.dart';
import 'package:awatv_player/src/backends/vlc_backend.dart';
import 'package:awatv_player/src/media_source.dart';
import 'package:awatv_player/src/player_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' show AudioTrack, SubtitleTrack, VideoTrack;

/// Thrown for unrecoverable player errors that should bubble up to the
/// caller rather than be reported via the state stream (e.g. illegal API
/// use after dispose).
class PlayerException implements Exception {
  PlayerException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'PlayerException: $message'
      '${cause == null ? '' : ' (cause: $cause)'}';
}

/// Thrown when callers ask for a backend the runtime cannot satisfy
/// (typically VLC on web/desktop). The factory catches this internally
/// and falls back to media_kit silently — only direct backend
/// constructors propagate it.
class PlayerBackendUnsupported implements Exception {
  PlayerBackendUnsupported(this.backend, this.reason);

  final PlayerBackend backend;
  final String reason;

  @override
  String toString() =>
      'PlayerBackendUnsupported: ${backend.name} -> $reason';
}

/// The available video-decoding backends.
///
/// `auto` lets [AwaPlayerController.create] pick the best option for
/// the host platform. `mediaKit` forces libmpv (or HTML5 on web).
/// `vlc` forces flutter_vlc_player; supported on iOS + Android only.
/// Selecting `vlc` on an unsupported platform silently falls back to
/// media_kit so the user always gets a working player.
enum PlayerBackend { auto, mediaKit, vlc }

/// Capability matrix for the running platform. Used by the picker UI to
/// dim options that would silently fall back at runtime.
class PlayerBackendCapabilities {
  const PlayerBackendCapabilities._();

  /// True when flutter_vlc_player has a real platform implementation
  /// for the current target. Web has no libVLC at all; the package's
  /// macOS / Windows / Linux side is unimplemented at the time of writing
  /// so we keep VLC scoped to mobile to avoid breaking those builds.
  static bool get vlcSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// One-line, human-readable explanation for why VLC is or isn't
  /// available on this device. Surfaced in the settings picker tooltip.
  static String get vlcReason => vlcSupported
      ? 'iOS / Android only — your device qualifies.'
      : 'iOS ve Android dışında VLC motoru desteklenmiyor.';
}

/// AWAtv's unified video-player controller — backend-agnostic surface.
///
/// Concrete implementations live in [MediaKitPlayerBackend] (libmpv on
/// native, HTML5 on web) and [VlcPlayerBackend] (flutter_vlc_player on
/// iOS / Android). Use the [AwaPlayerController.create] /
/// [AwaPlayerController.fromSource] / [AwaPlayerController.empty]
/// factories to construct one — they pick a backend based on the
/// requested [PlayerBackend] and the host platform's capabilities.
///
/// The widget layer is in `AwaPlayerView`; controls/overlays are the
/// host app's responsibility.
abstract class AwaPlayerController {
  /// Builds an idle controller with no source loaded.
  ///
  /// Use this when the caller wants to subscribe to the unified state
  /// stream before opening anything — typical for the player screen,
  /// which wires its UI listeners first and then calls
  /// [openWithFallbacks] with the variant chain.
  factory AwaPlayerController.empty({
    PlayerBackend backend = PlayerBackend.auto,
  }) {
    return _instantiate(null, backend);
  }

  /// Builds a controller and immediately opens [source] with autoplay.
  factory AwaPlayerController.fromSource(
    MediaSource source, {
    PlayerBackend backend = PlayerBackend.auto,
  }) {
    return _instantiate(source, backend);
  }

  /// Convenience alias for [AwaPlayerController.fromSource] — kept for
  /// the original draft contract (`AwaPlayerController.create(...)`).
  static AwaPlayerController create(
    MediaSource source, {
    PlayerBackend backend = PlayerBackend.auto,
  }) =>
      AwaPlayerController.fromSource(source, backend: backend);

  /// Picks the backend to use for [source] given the user's preference.
  ///
  /// `auto` resolves to:
  ///   - mediaKit on web (only HTML5 path; flutter_vlc_player has no web).
  ///   - mediaKit on iOS / Android / desktop by default — libmpv handles
  ///     most things and benchmarks faster.
  ///
  /// Note: we deliberately do not auto-route raw `.ts` to VLC any more.
  /// libmpv handles MPEG-TS reliably; promoting VLC for it caused panel
  /// regressions on devices where the VLC pod is missing. Users can still
  /// flip to VLC manually from the settings picker.
  static PlayerBackend resolveBackend(
    PlayerBackend requested,
    MediaSource? source,
  ) {
    if (requested == PlayerBackend.vlc) {
      return PlayerBackendCapabilities.vlcSupported
          ? PlayerBackend.vlc
          : PlayerBackend.mediaKit;
    }
    if (requested == PlayerBackend.mediaKit) return PlayerBackend.mediaKit;
    // auto:
    if (kIsWeb) return PlayerBackend.mediaKit;
    return PlayerBackend.mediaKit;
  }

  static AwaPlayerController _instantiate(
    MediaSource? source,
    PlayerBackend requested,
  ) {
    final picked = resolveBackend(requested, source);
    if (picked == PlayerBackend.vlc) {
      try {
        if (source == null) {
          return VlcPlayerBackend.empty();
        }
        return VlcPlayerBackend.fromSource(source);
      } on PlayerBackendUnsupported {
        // Defensive: if the platform check above said yes but the plugin
        // refuses to instantiate at runtime, never bubble — fall back so
        // the user still sees a player surface.
        if (source == null) return MediaKitPlayerBackend.empty();
        return MediaKitPlayerBackend.fromSource(source);
      }
    }
    if (source == null) return MediaKitPlayerBackend.empty();
    return MediaKitPlayerBackend.fromSource(source);
  }

  /// Initialises the underlying media engine(s) exactly once per process.
  ///
  /// Safe to call from anywhere; subsequent calls are no-ops. Must be
  /// invoked before constructing a controller, but the constructor calls
  /// it for you so app code rarely needs this directly.
  static Future<void> ensureInitialized() async {
    await MediaKitPlayerBackend.ensureInitialized();
    // flutter_vlc_player has no global init step — it spins up per
    // controller. Any future engine-wide setup goes here.
  }

  /// Identifier for the backend powering this controller — surfaced in
  /// settings UI and logs, never used for control flow.
  PlayerBackend get backend;

  // --- Lifecycle ---------------------------------------------------------
  /// Opens [source] in the player.
  Future<void> open(MediaSource source, {bool autoPlay = true});

  /// Opens [sources] in order until one starts playing.
  Future<void> openWithFallbacks(
    List<MediaSource> sources, {
    Duration perAttemptTimeout = const Duration(seconds: 4),
  });

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration to);

  /// Sets volume on a 0..100 scale.
  Future<void> setVolume(double volume);

  /// Sets playback speed. Implementations clamp to a sane UX range.
  Future<void> setSpeed(double speed);

  /// Releases the engine and closes all streams. Safe to call twice.
  Future<void> dispose();

  // --- State streams -----------------------------------------------------
  Stream<PlayerState> get states;
  Stream<Duration> get positions;
  Stream<Duration> get buffered;
  Stream<bool> get playing;
  Stream<bool> get completed;
  Stream<String> get errors;

  // --- Track listings ----------------------------------------------------
  List<VideoTrack> get videoTracks;
  List<AudioTrack> get audioTracks;
  List<SubtitleTrack> get subtitleTracks;
  VideoTrack? get currentVideoTrack;
  AudioTrack? get currentAudioTrack;
  SubtitleTrack? get currentSubtitleTrack;
  int? get videoWidth;
  int? get videoHeight;

  Stream<List<VideoTrack>> get videoTracksStream;
  Stream<List<AudioTrack>> get audioTracksStream;
  Stream<List<SubtitleTrack>> get subtitleTracksStream;
  Stream<VideoTrack> get currentVideoTrackStream;
  Stream<AudioTrack> get currentAudioTrackStream;
  Stream<SubtitleTrack> get currentSubtitleTrackStream;
  Stream<int?> get videoWidthStream;
  Stream<int?> get videoHeightStream;

  Future<void> setVideoTrack(VideoTrack track);
  Future<void> setAudioTrack(AudioTrack track);
  Future<void> setSubtitleTrack(SubtitleTrack track);

  /// Builds the platform video-surface widget for this controller.
  ///
  /// `AwaPlayerView` calls this so the same view widget can render the
  /// correct frame primitive for whichever backend the controller is
  /// using — `Video` for media_kit, `VlcPlayer` for the VLC backend.
  ///
  /// [wakelock], [pauseInBackground], and [resumeInForeground] match the
  /// media_kit `Video` widget's optional parameters and let the host
  /// platform-gate them to mobile only. Backends that don't support a
  /// flag silently treat it as no-op.
  Widget buildVideoSurface({
    required BoxFit fit,
    required Color backgroundColor,
    bool wakelock = false,
    bool pauseInBackground = false,
    bool resumeInForeground = false,
  });
}
