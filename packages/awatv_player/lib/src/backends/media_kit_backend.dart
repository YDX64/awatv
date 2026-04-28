import 'dart:async';

import 'package:awatv_player/src/awa_player_controller.dart';
import 'package:awatv_player/src/media_source.dart';
import 'package:awatv_player/src/player_state.dart';
import 'package:flutter/widgets.dart';
// Hide media_kit's `PlayerState` so our sealed class wins inside this file.
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';

/// libmpv-backed implementation of [AwaPlayerController].
///
/// On native platforms this drives `package:media_kit` over libmpv —
/// the canonical AWAtv path. On web it routes through media_kit's
/// HTML5 fallback (no libmpv, no native binaries shipped to browsers).
///
/// Surface area mirrors the abstract base 1:1 so call sites that hold
/// an `AwaPlayerController` keep working unmodified.
class MediaKitPlayerBackend implements AwaPlayerController {

  MediaKitPlayerBackend._() {
    _ensureInitializedSync();
    // 32 MiB buffer is a sweet spot for IPTV: large enough to ride out
    // brief network blips on slow mobile connections, small enough to
    // keep memory pressure modest on low-end Android TV boxes.
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'AWAtv',
      ),
    );
    _videoController = VideoController(_player);
    _wireUpStreams();
  }

  /// Builds an idle backend with no source loaded.
  factory MediaKitPlayerBackend.empty() => MediaKitPlayerBackend._();

  /// Builds a backend and immediately opens [source] with autoplay.
  factory MediaKitPlayerBackend.fromSource(MediaSource source) {
    final c = MediaKitPlayerBackend._();
    unawaited(c.open(source));
    return c;
  }

  static bool _initialized = false;

  /// Initialises libmpv exactly once per process. The factory calls this
  /// internally; only `AwaPlayerController.ensureInitialized` should hit
  /// it from app code.
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    MediaKit.ensureInitialized();
    _initialized = true;
  }

  void _ensureInitializedSync() {
    if (_initialized) return;
    MediaKit.ensureInitialized();
    _initialized = true;
  }

  late final Player _player;
  late final VideoController _videoController;

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

  // Subscriptions to the underlying media_kit streams; cancelled on dispose.
  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  // Cached snapshots used to compose unified PlayerState values.
  Duration _position = Duration.zero;
  Duration _bufferedPos = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _completed = false;
  bool _buffering = false;
  bool _disposed = false;

  PlayerState _currentState = const PlayerIdle();

  // Cached track snapshots so late subscribers immediately receive the
  // most recent value rather than waiting for the next emission.
  List<VideoTrack> _videoTracks = const <VideoTrack>[];
  List<AudioTrack> _audioTracks = const <AudioTrack>[];
  List<SubtitleTrack> _subtitleTracks = const <SubtitleTrack>[];
  VideoTrack? _currentVideoTrack;
  AudioTrack? _currentAudioTrack;
  SubtitleTrack? _currentSubtitleTrack;
  int? _videoWidth;
  int? _videoHeight;

  @override
  PlayerBackend get backend => PlayerBackend.mediaKit;

  /// The media_kit player. Exposed for advanced callers (screenshots,
  /// extra mpv properties, …) that already accept a media_kit-only path.
  Player get player => _player;

  /// The video controller backing the platform texture.
  VideoController get videoController => _videoController;

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

  @override
  Future<void> setVideoTrack(VideoTrack track) async {
    _ensureAlive();
    await _player.setVideoTrack(track);
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    _ensureAlive();
    await _player.setAudioTrack(track);
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    _ensureAlive();
    await _player.setSubtitleTrack(track);
  }

  @override
  Future<void> open(MediaSource source, {bool autoPlay = true}) async {
    _ensureAlive();
    _emitState(const PlayerLoading());
    _completed = false;

    try {
      // Fold the optional userAgent / referer into the headers map.
      // libmpv only accepts a User-Agent via the http-header-fields
      // option, which media_kit forwards as `httpHeaders` per Media.
      final headers = <String, String>{
        if (source.headers != null) ...source.headers!,
        if (source.userAgent != null) 'User-Agent': source.userAgent!,
        if (source.referer != null) 'Referer': source.referer!,
      };

      await _player.open(
        Media(
          source.url,
          httpHeaders: headers.isEmpty ? null : headers,
          extras: source.title == null ? null : {'title': source.title},
        ),
        play: autoPlay,
      );

      // Sidecar subtitle: load after open() so the primary track is set up.
      if (source.subtitleUrl != null && source.subtitleUrl!.isNotEmpty) {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(source.subtitleUrl!),
        );
      }
    } catch (e) {
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
      try {
        await _player.stop();
      } on Object {
        // Best-effort; we're about to open a fresh source anyway.
      }
    }

    final msg = lastError ?? 'all sources failed';
    _emitState(PlayerError(msg));
    throw PlayerException('openWithFallbacks: $msg');
  }

  @override
  Future<void> play() async {
    _ensureAlive();
    await _player.play();
  }

  @override
  Future<void> pause() async {
    _ensureAlive();
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    _ensureAlive();
    await _player.stop();
    _emitState(const PlayerIdle());
  }

  @override
  Future<void> seek(Duration to) async {
    _ensureAlive();
    await _player.seek(to);
  }

  @override
  Future<void> setVolume(double volume) async {
    _ensureAlive();
    final clamped = volume.clamp(0.0, 100.0);
    await _player.setVolume(clamped);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _ensureAlive();
    final clamped = speed.clamp(0.25, 4.0);
    await _player.setRate(clamped);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();

    await _player.dispose();

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
    return ColoredBox(
      color: backgroundColor,
      child: Video(
        controller: _videoController,
        fit: fit,
        fill: backgroundColor,
        // Disable built-in controls; the host app provides its own UI.
        // Spelled out as a builder to dodge a typing-quirk where the bare
        // `NoVideoControls` constant resolves to dynamic in some lints.
        controls: (VideoState state) => const SizedBox.shrink(),
        // Keep the screen awake during playback on mobile only.
        wakelock: wakelock,
        // Mobile: let the platform pause us on background and resume us
        // on foreground — matches OS conventions. Desktop / web: never
        // auto pause on focus loss; the host app's lifecycle logic
        // decides.
        pauseUponEnteringBackgroundMode: pauseInBackground,
        resumeUponEnteringForegroundMode: resumeInForeground,
      ),
    );
  }

  // --- internals ---------------------------------------------------------

  void _ensureAlive() {
    if (_disposed) {
      throw PlayerException('Controller has been disposed.');
    }
  }

  /// Hooks every relevant media_kit stream and re-emits a unified
  /// [PlayerState] whenever a meaningful field changes.
  void _wireUpStreams() {
    _subs
      ..add(_player.stream.position.listen((p) {
        _position = p;
        _positionCtrl.add(p);
        _recomputeState();
      }))
      ..add(_player.stream.duration.listen((d) {
        _duration = d;
        _recomputeState();
      }))
      ..add(_player.stream.buffer.listen((b) {
        _bufferedPos = b;
        _bufferedCtrl.add(b);
        _recomputeState();
      }))
      ..add(_player.stream.playing.listen((p) {
        _playing = p;
        _playingCtrl.add(p);
        _recomputeState();
      }))
      ..add(_player.stream.completed.listen((c) {
        _completed = c;
        _completedCtrl.add(c);
        if (c) {
          _emitState(const PlayerEnded());
        } else {
          _recomputeState();
        }
      }))
      ..add(_player.stream.buffering.listen((b) {
        _buffering = b;
        _recomputeState();
      }))
      ..add(_player.stream.error.listen((e) {
        if (e.isEmpty) return;
        _errorsCtrl.add(e);
        _emitState(PlayerError(e));
      }))
      ..add(_player.stream.tracks.listen((Tracks t) {
        _videoTracks = t.video;
        _audioTracks = t.audio;
        _subtitleTracks = t.subtitle;
        _videoTracksCtrl.add(_videoTracks);
        _audioTracksCtrl.add(_audioTracks);
        _subtitleTracksCtrl.add(_subtitleTracks);
      }))
      ..add(_player.stream.track.listen((Track sel) {
        _currentVideoTrack = sel.video;
        _currentAudioTrack = sel.audio;
        _currentSubtitleTrack = sel.subtitle;
        _currentVideoTrackCtrl.add(sel.video);
        _currentAudioTrackCtrl.add(sel.audio);
        _currentSubtitleTrackCtrl.add(sel.subtitle);
      }))
      ..add(_player.stream.width.listen((int? w) {
        _videoWidth = w;
        _videoWidthCtrl.add(w);
      }))
      ..add(_player.stream.height.listen((int? h) {
        _videoHeight = h;
        _videoHeightCtrl.add(h);
      }));
  }

  void _recomputeState() {
    if (_disposed) return;
    if (_currentState is PlayerError) {
      // Sticky: stay in error until the next successful open().
      return;
    }
    if (_completed) {
      _emitState(const PlayerEnded());
      return;
    }
    if (_buffering) {
      _emitState(const PlayerLoading());
      return;
    }
    final total = _duration > Duration.zero ? _duration : null;
    if (_playing) {
      _emitState(PlayerPlaying(
        position: _position,
        buffered: _bufferedPos,
        total: total,
      ));
    } else {
      _emitState(PlayerPaused(position: _position, total: total));
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
      // Position/buffered changes are streamed separately; we still emit
      // a new state object on every tick so reactive frameworks (Riverpod
      // selectors, ValueListenable, ...) can pick up position from the
      // unified stream if they choose to.
      PlayerPlaying() => false,
      PlayerPaused() => false,
    };
  }
}
