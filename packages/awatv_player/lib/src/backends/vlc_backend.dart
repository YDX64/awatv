import 'dart:async';

import 'package:awatv_player/src/awa_player_controller.dart';
import 'package:awatv_player/src/backends/media_kit_backend.dart' show MediaKitPlayerBackend;
import 'package:awatv_player/src/media_source.dart';
import 'package:awatv_player/src/player_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart' as vlc;
import 'package:media_kit/media_kit.dart' show AudioTrack, SubtitleTrack, VideoTrack;

/// VLC-backed implementation of [AwaPlayerController].
///
/// Wraps `package:flutter_vlc_player` (libVLC under the hood) for tough
/// codecs / DRM / panel quirks where libmpv falls over. Limited to iOS
/// and Android — flutter_vlc_player has no implementation for web,
/// macOS, Windows or Linux at the time of writing, so the factory layer
/// silently routes those platforms back to [MediaKitPlayerBackend].
///
/// Track types are re-used from media_kit (re-exported by the package's
/// public API) so call sites don't have to branch on which backend is
/// running. We synthesise `VideoTrack`, `AudioTrack` and `SubtitleTrack`
/// instances from libVLC's integer track ids.
class VlcPlayerBackend implements AwaPlayerController {

  VlcPlayerBackend._();

  /// Builds an idle backend. The underlying VLC controller cannot be
  /// constructed without a media URL, so we defer until [open] is called.
  factory VlcPlayerBackend.empty() {
    if (!PlayerBackendCapabilities.vlcSupported) {
      throw PlayerBackendUnsupported(
        PlayerBackend.vlc,
        PlayerBackendCapabilities.vlcReason,
      );
    }
    return VlcPlayerBackend._();
  }

  /// Builds a backend and immediately opens [source] with autoplay.
  factory VlcPlayerBackend.fromSource(MediaSource source) {
    if (!PlayerBackendCapabilities.vlcSupported) {
      throw PlayerBackendUnsupported(
        PlayerBackend.vlc,
        PlayerBackendCapabilities.vlcReason,
      );
    }
    final backend = VlcPlayerBackend._();
    final controller = _buildVlcController(source);
    backend._activeController = controller;
    backend._attachListeners(controller, source);
    return backend;
  }

  // The active flutter_vlc_player controller. Replaced on every [open]
  // because libVLC requires a fresh instance to switch options like the
  // user-agent — `setMediaFromNetwork` only swaps the URL, not the
  // surrounding HTTP context.
  vlc.VlcPlayerController? _activeController;

  // Listener bookkeeping so we can detach cleanly when [open] swaps the
  // underlying controller and on [dispose].
  VoidCallback? _activeListener;
  vlc.VlcPlayerController? _listeningOn;

  // Fan-out controllers. Broadcast so multiple widgets can subscribe.
  final StreamController<PlayerState> _stateCtrl =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _bufferedCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingCtrl =
      StreamController<bool>.broadcast();
  final StreamController<bool> _completedCtrl =
      StreamController<bool>.broadcast();
  final StreamController<String> _errorsCtrl =
      StreamController<String>.broadcast();
  final StreamController<List<VideoTrack>> _videoTracksCtrl =
      StreamController<List<VideoTrack>>.broadcast();
  final StreamController<List<AudioTrack>> _audioTracksCtrl =
      StreamController<List<AudioTrack>>.broadcast();
  final StreamController<List<SubtitleTrack>> _subtitleTracksCtrl =
      StreamController<List<SubtitleTrack>>.broadcast();
  final StreamController<VideoTrack> _currentVideoTrackCtrl =
      StreamController<VideoTrack>.broadcast();
  final StreamController<AudioTrack> _currentAudioTrackCtrl =
      StreamController<AudioTrack>.broadcast();
  final StreamController<SubtitleTrack> _currentSubtitleTrackCtrl =
      StreamController<SubtitleTrack>.broadcast();
  final StreamController<int?> _videoWidthCtrl =
      StreamController<int?>.broadcast();
  final StreamController<int?> _videoHeightCtrl =
      StreamController<int?>.broadcast();

  // Cached snapshots so late subscribers immediately receive the most
  // recent value, mirroring the media_kit backend's contract.
  PlayerState _currentState = const PlayerIdle();
  Duration _position = Duration.zero;
  Duration _bufferedPos = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _completed = false;
  bool _disposed = false;

  List<VideoTrack> _videoTracks = const <VideoTrack>[];
  List<AudioTrack> _audioTracks = const <AudioTrack>[];
  List<SubtitleTrack> _subtitleTracks = const <SubtitleTrack>[];
  VideoTrack? _currentVideoTrack;
  AudioTrack? _currentAudioTrack;
  SubtitleTrack? _currentSubtitleTrack;
  int? _videoWidth;
  int? _videoHeight;

  // Track-list refresh debouncer: libVLC needs a beat after the
  // PlayingState transition before getAudioTracks/getSpuTracks return
  // the real list. Polling it via a one-shot timer keeps the cost low.
  Timer? _trackRefreshTimer;

  @override
  PlayerBackend get backend => PlayerBackend.vlc;

  /// Exposes the active VlcPlayerController for advanced consumers — the
  /// settings sheet, debug overlays, etc. Null until the first [open] in
  /// the empty-controller flow.
  vlc.VlcPlayerController? get vlcController => _activeController;

  // --- Streams -----------------------------------------------------------
  @override
  Stream<PlayerState> get states async* {
    yield _currentState;
    yield* _stateCtrl.stream;
  }

  @override
  Stream<Duration> get positions => _positionCtrl.stream;
  @override
  Stream<Duration> get buffered => _bufferedCtrl.stream;
  @override
  Stream<bool> get playing => _playingCtrl.stream;
  @override
  Stream<bool> get completed => _completedCtrl.stream;
  @override
  Stream<String> get errors => _errorsCtrl.stream;

  @override
  List<VideoTrack> get videoTracks =>
      List<VideoTrack>.unmodifiable(_videoTracks);
  @override
  List<AudioTrack> get audioTracks =>
      List<AudioTrack>.unmodifiable(_audioTracks);
  @override
  List<SubtitleTrack> get subtitleTracks =>
      List<SubtitleTrack>.unmodifiable(_subtitleTracks);

  @override
  VideoTrack? get currentVideoTrack => _currentVideoTrack;
  @override
  AudioTrack? get currentAudioTrack => _currentAudioTrack;
  @override
  SubtitleTrack? get currentSubtitleTrack => _currentSubtitleTrack;

  @override
  int? get videoWidth => _videoWidth;
  @override
  int? get videoHeight => _videoHeight;

  @override
  Stream<List<VideoTrack>> get videoTracksStream async* {
    yield _videoTracks;
    yield* _videoTracksCtrl.stream;
  }

  @override
  Stream<List<AudioTrack>> get audioTracksStream async* {
    yield _audioTracks;
    yield* _audioTracksCtrl.stream;
  }

  @override
  Stream<List<SubtitleTrack>> get subtitleTracksStream async* {
    yield _subtitleTracks;
    yield* _subtitleTracksCtrl.stream;
  }

  @override
  Stream<VideoTrack> get currentVideoTrackStream async* {
    final v = _currentVideoTrack;
    if (v != null) yield v;
    yield* _currentVideoTrackCtrl.stream;
  }

  @override
  Stream<AudioTrack> get currentAudioTrackStream async* {
    final a = _currentAudioTrack;
    if (a != null) yield a;
    yield* _currentAudioTrackCtrl.stream;
  }

  @override
  Stream<SubtitleTrack> get currentSubtitleTrackStream async* {
    final s = _currentSubtitleTrack;
    if (s != null) yield s;
    yield* _currentSubtitleTrackCtrl.stream;
  }

  @override
  Stream<int?> get videoWidthStream async* {
    yield _videoWidth;
    yield* _videoWidthCtrl.stream;
  }

  @override
  Stream<int?> get videoHeightStream async* {
    yield _videoHeight;
    yield* _videoHeightCtrl.stream;
  }

  // --- Track selection ---------------------------------------------------

  @override
  Future<void> setVideoTrack(VideoTrack track) async {
    // libVLC does not expose multi-bitrate switching the way HLS-aware
    // libmpv does — the underlying API is per-stream-id only. We keep
    // the call a successful no-op for `auto`/`no` so the settings sheet
    // can still cycle through the listing without throwing.
    _ensureAlive();
    final c = _activeController;
    if (c == null) return;
    if (track.id == 'no') {
      // No safe way to disable video on libVLC without tearing down the
      // controller; treat as a soft no-op.
      _currentVideoTrack = track;
      _currentVideoTrackCtrl.add(track);
      return;
    }
    _currentVideoTrack = track;
    _currentVideoTrackCtrl.add(track);
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    _ensureAlive();
    final c = _activeController;
    if (c == null) return;
    final id = int.tryParse(track.id);
    if (id == null) return;
    try {
      await c.setAudioTrack(id);
      _currentAudioTrack = track;
      _currentAudioTrackCtrl.add(track);
    } on Object catch (e) {
      _errorsCtrl.add('VLC: failed to set audio track: $e');
    }
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    _ensureAlive();
    final c = _activeController;
    if (c == null) return;
    if (track.id == 'no') {
      try {
        // Track id -1 disables subtitles in libVLC.
        await c.setSpuTrack(-1);
        _currentSubtitleTrack = track;
        _currentSubtitleTrackCtrl.add(track);
      } on Object catch (e) {
        _errorsCtrl.add('VLC: failed to disable subtitle: $e');
      }
      return;
    }
    final id = int.tryParse(track.id);
    if (id == null) return;
    try {
      await c.setSpuTrack(id);
      _currentSubtitleTrack = track;
      _currentSubtitleTrackCtrl.add(track);
    } on Object catch (e) {
      _errorsCtrl.add('VLC: failed to set subtitle track: $e');
    }
  }

  // --- Lifecycle ---------------------------------------------------------

  @override
  Future<void> open(MediaSource source, {bool autoPlay = true}) async {
    _ensureAlive();
    _emitState(const PlayerLoading());
    _completed = false;

    try {
      // Tear down any previous controller before constructing a new one.
      // libVLC keeps a dedicated rendering surface per controller; the
      // VlcPlayer widget rebuilds against the new instance via the
      // `buildVideoSurface` widget which observes [vlcController].
      await _disposeActiveController();

      final controller = _buildVlcController(source, autoPlay: autoPlay);
      _activeController = controller;
      _attachListeners(controller, source);

      // The `network` constructor begins playback automatically when
      // autoPlay is true; for paused-open we explicitly pause once the
      // engine reports ready (the listener does that below).
    } on Object catch (e) {
      _emitState(PlayerError('Failed to open source: $e', cause: e));
      _errorsCtrl.add(e.toString());
      throw PlayerException('open() failed', e);
    }
  }

  @override
  Future<void> openWithFallbacks(
    List<MediaSource> sources, {
    Duration perAttemptTimeout = const Duration(seconds: 4),
  }) async {
    _ensureAlive();
    if (sources.isEmpty) {
      throw PlayerException('openWithFallbacks called with no sources');
    }
    String? lastError;
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      final isLast = i == sources.length - 1;
      try {
        await open(source);
      } on PlayerException catch (e) {
        lastError = e.message;
        if (isLast) break;
        continue;
      }

      final completer = Completer<bool>();
      late final StreamSubscription<PlayerState> sub;
      sub = states.listen((PlayerState state) {
        if (completer.isCompleted) return;
        if (state is PlayerPlaying) {
          completer.complete(true);
        } else if (state is PlayerError) {
          lastError = state.message;
          completer.complete(false);
        }
      });
      Timer? timer;
      timer = Timer(perAttemptTimeout, () {
        if (completer.isCompleted) return;
        if (_bufferedPos > Duration.zero || _position > Duration.zero) {
          completer.complete(true);
        } else {
          lastError = 'Stream did not start within '
              '${perAttemptTimeout.inSeconds}s';
          completer.complete(false);
        }
      });

      final ok = await completer.future;
      timer.cancel();
      await sub.cancel();
      if (ok) return;
      if (isLast) break;
    }

    final msg = lastError ?? 'all sources failed';
    _emitState(PlayerError(msg));
    throw PlayerException('openWithFallbacks: $msg');
  }

  @override
  Future<void> play() async {
    _ensureAlive();
    final c = _activeController;
    if (c == null) return;
    await c.play();
  }

  @override
  Future<void> pause() async {
    _ensureAlive();
    final c = _activeController;
    if (c == null) return;
    await c.pause();
  }

  @override
  Future<void> stop() async {
    _ensureAlive();
    final c = _activeController;
    if (c == null) {
      _emitState(const PlayerIdle());
      return;
    }
    try {
      await c.stop();
    } on Object {
      // Best-effort.
    }
    _emitState(const PlayerIdle());
  }

  @override
  Future<void> seek(Duration to) async {
    _ensureAlive();
    final c = _activeController;
    if (c == null) return;
    await c.seekTo(to);
  }

  @override
  Future<void> setVolume(double volume) async {
    _ensureAlive();
    final c = _activeController;
    if (c == null) return;
    final clamped = volume.clamp(0.0, 100.0).round();
    await c.setVolume(clamped);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _ensureAlive();
    final c = _activeController;
    if (c == null) return;
    final clamped = speed.clamp(0.25, 4.0);
    await c.setPlaybackSpeed(clamped);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _trackRefreshTimer?.cancel();
    _trackRefreshTimer = null;

    await _disposeActiveController();

    await _stateCtrl.close();
    await _positionCtrl.close();
    await _bufferedCtrl.close();
    await _playingCtrl.close();
    await _completedCtrl.close();
    await _errorsCtrl.close();
    await _videoTracksCtrl.close();
    await _audioTracksCtrl.close();
    await _subtitleTracksCtrl.close();
    await _currentVideoTrackCtrl.close();
    await _currentAudioTrackCtrl.close();
    await _currentSubtitleTrackCtrl.close();
    await _videoWidthCtrl.close();
    await _videoHeightCtrl.close();
  }

  @override
  Widget buildVideoSurface({
    required BoxFit fit,
    required Color backgroundColor,
    bool wakelock = false,
    bool pauseInBackground = false,
    bool resumeInForeground = false,
  }) {
    // flutter_vlc_player has no equivalent of media_kit's wakelock /
    // background flags — libVLC keeps decoding while the platform
    // suspends the app, and waking the screen is a host-app concern on
    // iOS / Android (handled via `wakelock_plus` upstream when needed).
    // We accept the parameters for API parity and ignore them here.
    return _VlcSurface(
      backend: this,
      fit: fit,
      backgroundColor: backgroundColor,
    );
  }

  // --- internals ---------------------------------------------------------

  void _ensureAlive() {
    if (_disposed) {
      throw PlayerException('Controller has been disposed.');
    }
  }

  void _emitState(PlayerState s) {
    if (_disposed) return;
    if (_isSameState(_currentState, s)) return;
    _currentState = s;
    _stateCtrl.add(s);
  }

  bool _isSameState(PlayerState a, PlayerState b) {
    if (a.runtimeType != b.runtimeType) return false;
    return switch (a) {
      PlayerIdle() => true,
      PlayerLoading() => true,
      PlayerEnded() => true,
      PlayerError(message: final m) =>
        b is PlayerError && b.message == m,
      PlayerPlaying() => false,
      PlayerPaused() => false,
    };
  }

  /// Constructs a `VlcPlayerController.network` for [source], folding
  /// the optional headers/userAgent/referer into libVLC's
  /// `--http-user-agent`, `--http-referrer`, and `--http-headers` flags.
  static vlc.VlcPlayerController _buildVlcController(
    MediaSource source, {
    bool autoPlay = true,
  }) {
    final advancedOptions = <String>[];
    final httpOptions = <String>[];

    final ua = source.userAgent;
    if (ua != null && ua.isNotEmpty) {
      httpOptions.add('--http-user-agent=$ua');
    }
    final referer = source.referer;
    if (referer != null && referer.isNotEmpty) {
      httpOptions.add('--http-referrer=$referer');
    }
    final headers = source.headers;
    if (headers != null && headers.isNotEmpty) {
      // libVLC accepts a single CRLF-separated string via --http-headers.
      final encoded = headers.entries
          .map((MapEntry<String, String> e) => '${e.key}: ${e.value}')
          .join('\r\n');
      httpOptions.add('--http-headers=$encoded');
    }

    // Smaller network cache (1500 ms) keeps live IPTV latency low; libmpv
    // peers with about the same window. Tunable later via MediaSource
    // extras if a panel really needs more.
    advancedOptions.add(':network-caching=1500');

    return vlc.VlcPlayerController.network(
      source.url,
      autoPlay: autoPlay,
      options: vlc.VlcPlayerOptions(
        advanced: vlc.VlcAdvancedOptions(advancedOptions),
        http: vlc.VlcHttpOptions(httpOptions),
        // Default RTSP / extras stay at library defaults.
        subtitle: vlc.VlcSubtitleOptions(<String>[]),
        video: vlc.VlcVideoOptions(<String>[]),
        rtp: vlc.VlcRtpOptions(<String>[]),
      ),
    );
  }

  /// Wires the value-listenable on [c] up to our broadcast streams.
  /// Replays the cached snapshot via [_emitState] so subscribers that
  /// attach mid-flight see the latest state immediately.
  void _attachListeners(
    vlc.VlcPlayerController c,
    MediaSource source,
  ) {
    // Detach any prior listener so we don't duplicate work after open().
    final prev = _listeningOn;
    final prevListener = _activeListener;
    if (prev != null && prevListener != null) {
      try {
        prev.removeListener(prevListener);
      } on Object {
        // The controller may already be disposed; harmless.
      }
    }

    void listener() {
      if (_disposed) return;
      if (!c.value.isInitialized) return;
      _onValueChanged(c, source);
    }

    c.addListener(listener);
    _activeListener = listener;
    _listeningOn = c;

    // Subtitle sidecar — libVLC's API takes a plain URL/path. The
    // initial controller spins up async, so wait for `isInitialized`
    // before attempting the call.
    final sub = source.subtitleUrl;
    if (sub != null && sub.isNotEmpty) {
      void onceInitialized() {
        if (!c.value.isInitialized) return;
        c.removeListener(onceInitialized);
        try {
          c.addSubtitleFromNetwork(sub);
        } on Object {
          // Subtitle failures are non-fatal.
        }
      }

      c.addListener(onceInitialized);
    }
  }

  void _onValueChanged(
    vlc.VlcPlayerController c,
    MediaSource source,
  ) {
    final v = c.value;

    // Position / duration / buffered.
    if (v.position != _position) {
      _position = v.position;
      if (!_disposed) _positionCtrl.add(v.position);
    }
    if (v.duration != _duration) {
      _duration = v.duration;
    }
    // libVLC reports buffered as a percentage of total; convert to a
    // duration so the AwaPlayerController contract holds.
    final bufferedDuration = _duration > Duration.zero
        ? _duration * (v.bufferPercent.clamp(0, 100) / 100.0)
        : Duration.zero;
    if (bufferedDuration != _bufferedPos) {
      _bufferedPos = bufferedDuration;
      if (!_disposed) _bufferedCtrl.add(bufferedDuration);
    }

    // Native pixel size.
    final w = v.size.width.toInt();
    final h = v.size.height.toInt();
    if (w > 0 && w != _videoWidth) {
      _videoWidth = w;
      if (!_disposed) _videoWidthCtrl.add(w);
    }
    if (h > 0 && h != _videoHeight) {
      _videoHeight = h;
      if (!_disposed) _videoHeightCtrl.add(h);
    }

    // Hard error: surface and stick.
    if (v.hasError) {
      final msg = v.errorDescription.isNotEmpty
          ? v.errorDescription
          : 'VLC backend reported an error.';
      _errorsCtrl.add(msg);
      _emitState(PlayerError(msg));
      return;
    }

    // Map flutter_vlc_player's PlayingState to our sealed PlayerState.
    final playingNow = v.playingState == vlc.PlayingState.playing;
    if (playingNow != _playing) {
      _playing = playingNow;
      if (!_disposed) _playingCtrl.add(playingNow);
    }
    final endedNow = v.playingState == vlc.PlayingState.ended;
    if (endedNow != _completed) {
      _completed = endedNow;
      if (!_disposed) _completedCtrl.add(endedNow);
    }

    // Recompute the unified state. flutter_vlc_player exposes:
    //   initializing → first wiring of the engine before any media
    //   initialized → ready, no media loaded yet (we treat as Loading)
    //   buffering → mid-stream rebuffer or pre-roll
    //   playing → live playback (mapped above)
    //   paused / stopped → user-paused or end-of-stream-without-EOF
    //   ended → VOD reached EOF
    //   error → handled by the `hasError` early-return above
    //   recording → libVLC recording mode; treat as playing for our UX
    if (endedNow) {
      _emitState(const PlayerEnded());
    } else if (v.playingState == vlc.PlayingState.buffering ||
        v.playingState == vlc.PlayingState.initializing ||
        v.playingState == vlc.PlayingState.initialized) {
      _emitState(const PlayerLoading());
    } else if (playingNow ||
        v.playingState == vlc.PlayingState.recording) {
      final total = _duration > Duration.zero ? _duration : null;
      _emitState(PlayerPlaying(
        position: _position,
        buffered: _bufferedPos,
        total: total,
      ));
    } else if (v.playingState == vlc.PlayingState.paused ||
        v.playingState == vlc.PlayingState.stopped) {
      final total = _duration > Duration.zero ? _duration : null;
      _emitState(PlayerPaused(position: _position, total: total));
    }

    // Track listings tend to resolve a tick after `playing` flips on.
    // Schedule a single refresh shortly after the first transition;
    // libVLC settles the audio and SPU lists by then.
    if (playingNow && _trackRefreshTimer == null) {
      _trackRefreshTimer = Timer(const Duration(milliseconds: 600), () {
        unawaited(_refreshTracks(c));
      });
    }
  }

  /// Pulls audio + subtitle track lists from libVLC and translates them
  /// into media_kit-shaped `AudioTrack` / `SubtitleTrack` instances so
  /// the host UI can render the same pickers regardless of backend.
  ///
  /// libVLC does not expose multi-bitrate "video tracks" the way HLS-aware
  /// libmpv does — it's per-stream-id only — so we surface a synthetic
  /// `auto` entry for the video list to keep the picker non-empty.
  Future<void> _refreshTracks(vlc.VlcPlayerController c) async {
    if (_disposed) return;
    try {
      final audioMap = await c.getAudioTracks();
      final spuMap = await c.getSpuTracks();
      final activeAudio = await c.getAudioTrack();
      final activeSpu = await c.getSpuTrack();

      final audio = <AudioTrack>[];
      audioMap.forEach((int id, String name) {
        audio.add(AudioTrack.uri(id.toString(), title: name));
      });
      _audioTracks = audio;
      if (!_disposed) _audioTracksCtrl.add(audio);

      final subtitle = <SubtitleTrack>[
        SubtitleTrack.no(),
      ];
      spuMap.forEach((int id, String name) {
        subtitle.add(SubtitleTrack.uri(id.toString(), title: name));
      });
      _subtitleTracks = subtitle;
      if (!_disposed) _subtitleTracksCtrl.add(subtitle);

      // Synthetic single-entry video list so the Quality section in the
      // settings sheet doesn't show an empty hint when the user is on
      // VLC. libVLC exposes only one renderable video stream.
      final video = <VideoTrack>[
        VideoTrack.auto(),
      ];
      _videoTracks = video;
      if (!_disposed) _videoTracksCtrl.add(video);
      _currentVideoTrack = video.first;
      if (!_disposed) _currentVideoTrackCtrl.add(video.first);

      // Best-effort current track resolution.
      if (activeAudio != null) {
        final match = audio.where(
          (AudioTrack t) => t.id == activeAudio.toString(),
        );
        if (match.isNotEmpty) {
          _currentAudioTrack = match.first;
          if (!_disposed) _currentAudioTrackCtrl.add(match.first);
        }
      }
      if (activeSpu != null && activeSpu == -1) {
        _currentSubtitleTrack = SubtitleTrack.no();
        if (!_disposed) _currentSubtitleTrackCtrl.add(_currentSubtitleTrack!);
      } else if (activeSpu != null) {
        final match = subtitle.where(
          (SubtitleTrack t) => t.id == activeSpu.toString(),
        );
        if (match.isNotEmpty) {
          _currentSubtitleTrack = match.first;
          if (!_disposed) _currentSubtitleTrackCtrl.add(match.first);
        }
      }
    } on Object catch (e) {
      if (kDebugMode) debugPrint('VlcPlayerBackend: track refresh failed: $e');
    } finally {
      _trackRefreshTimer = null;
    }
  }

  Future<void> _disposeActiveController() async {
    final active = _activeController;
    if (active == null) return;
    final listener = _activeListener;
    if (listener != null) {
      try {
        active.removeListener(listener);
      } on Object {
        // Already gone; harmless.
      }
    }
    _activeListener = null;
    _listeningOn = null;
    _activeController = null;
    try {
      await active.stopRendererScanning();
    } on Object {
      // Not all platforms support renderer scanning; ignore.
    }
    try {
      await active.dispose();
    } on Object {
      // Best-effort cleanup; the ProviderScope teardown can race here.
    }
  }
}

/// Internal widget that hosts the `VlcPlayer` for a [VlcPlayerBackend].
///
/// Watches the backend for `vlcController` swaps caused by
/// re-`open()`-ing a source so the surface always renders the live
/// instance. If the backend has not opened anything yet, paints a black
/// placeholder so the AwaPlayerView surface size is stable.
class _VlcSurface extends StatefulWidget {
  const _VlcSurface({
    required this.backend,
    required this.fit,
    required this.backgroundColor,
  });

  final VlcPlayerBackend backend;
  final BoxFit fit;
  final Color backgroundColor;

  @override
  State<_VlcSurface> createState() => _VlcSurfaceState();
}

class _VlcSurfaceState extends State<_VlcSurface> {
  // We rebuild whenever the backend swaps controllers via [open()].
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    // The backend doesn't expose a controller stream — it does emit state
    // transitions, and any open() will produce at least PlayerLoading.
    // That's enough of a signal to call setState and re-read
    // `vlcController`.
    _stateSub = widget.backend.states.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.backend.vlcController;
    if (c == null) {
      // Placeholder until the first open() — keeps the layout stable.
      return ColoredBox(color: widget.backgroundColor);
    }
    return ColoredBox(
      color: widget.backgroundColor,
      child: Center(
        child: AspectRatio(
          aspectRatio: _resolveAspectRatio(c),
          child: vlc.VlcPlayer(
            controller: c,
            aspectRatio: _resolveAspectRatio(c),
            placeholder: ColoredBox(color: widget.backgroundColor),
          ),
        ),
      ),
    );
  }

  /// libVLC sometimes reports a 0/0 size before the first frame arrives.
  /// Falling back to 16/9 keeps the surface from collapsing to a sliver.
  double _resolveAspectRatio(vlc.VlcPlayerController c) {
    final size = c.value.size;
    if (size.width == 0 || size.height == 0) return 16 / 9;
    return size.width / size.height;
  }
}
