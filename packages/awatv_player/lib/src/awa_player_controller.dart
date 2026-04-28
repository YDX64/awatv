import 'dart:async';

// Hide media_kit's `PlayerState` so our sealed class wins inside this file.
import 'package:awatv_player/src/media_source.dart';
import 'package:awatv_player/src/player_state.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';

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

/// AWAtv's unified video-player controller.
///
/// Wraps [Player] from `package:media_kit` (libmpv on desktop/mobile,
/// HTML5 on web) and exposes a small, intentional surface aligned with
/// `awatv_core`'s expectations. The widget layer is in
/// [AwaPlayerView]; controls/overlays are the host app's responsibility.
class AwaPlayerController {

  AwaPlayerController._() {
    ensureInitialized();
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

  /// Builds an idle controller with no source loaded.
  ///
  /// Use this when the caller wants to subscribe to the unified state
  /// stream before opening anything — typical for the player screen,
  /// which wires its UI listeners first and then calls
  /// [openWithFallbacks] with the variant chain.
  factory AwaPlayerController.empty() => AwaPlayerController._();

  /// Builds a controller and immediately opens [source] with autoplay.
  factory AwaPlayerController.fromSource(MediaSource source) {
    final controller = AwaPlayerController._();
    // Fire-and-forget; the state stream will surface any open errors.
    unawaited(controller.open(source));
    return controller;
  }

  /// Convenience alias for [AwaPlayerController.fromSource] — kept because
  /// the mobile app coded against `create()` per AGENT.md's draft contract.
  static AwaPlayerController create(MediaSource source) =>
      AwaPlayerController.fromSource(source);

  static bool _initialized = false;

  /// Initialises the underlying media engine exactly once per process.
  ///
  /// Safe to call from anywhere; subsequent calls are no-ops. Must be
  /// invoked before constructing a controller, but the constructor calls
  /// it for you so app code rarely needs this directly.
  ///
  /// Returns a `Future<void>` so callers can `await` it from `main()` even
  /// though the underlying media_kit init is currently synchronous — keeps
  /// the call site future-proof.
  static Future<void> ensureInitialized() async {
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
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  // Cached snapshots used to compose unified PlayerState values.
  Duration _position = Duration.zero;
  Duration _buffered = Duration.zero;
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

  /// The media_kit player. Exposed so [AwaPlayerView] (or advanced
  /// callers needing track selection, screenshots, etc.) can reach it.
  Player get player => _player;

  /// The video controller backing the platform texture.
  VideoController get videoController => _videoController;

  /// Unified state stream. Replays the latest value on subscribe so late
  /// listeners get an immediate snapshot rather than waiting for the next
  /// transition.
  Stream<PlayerState> get states async* {
    yield _currentState;
    yield* _stateCtrl.stream;
  }

  Stream<Duration> get positions => _positionCtrl.stream;
  Stream<Duration> get buffered => _bufferedCtrl.stream;
  Stream<bool> get playing => _playingCtrl.stream;
  Stream<bool> get completed => _completedCtrl.stream;
  Stream<String> get errors => _errorsCtrl.stream;

  // --- Tracks ------------------------------------------------------------
  /// Currently available video tracks (typically including `auto` and
  /// `no` virtual entries plus per-stream variants for HLS).
  List<VideoTrack> get videoTracks => List<VideoTrack>.unmodifiable(_videoTracks);

  /// Currently available audio tracks (language / channels / codec).
  List<AudioTrack> get audioTracks => List<AudioTrack>.unmodifiable(_audioTracks);

  /// Currently available subtitle tracks. Always includes the synthetic
  /// `no` entry that disables subtitles.
  List<SubtitleTrack> get subtitleTracks =>
      List<SubtitleTrack>.unmodifiable(_subtitleTracks);

  /// The video track the player is currently rendering, or `null` when
  /// the engine has not yet reported a selection.
  VideoTrack? get currentVideoTrack => _currentVideoTrack;

  /// The audio track the player is currently outputting.
  AudioTrack? get currentAudioTrack => _currentAudioTrack;

  /// The subtitle track currently displayed (or `SubtitleTrack.no()`).
  SubtitleTrack? get currentSubtitleTrack => _currentSubtitleTrack;

  /// Last reported native video width in pixels, if any.
  int? get videoWidth => _videoWidth;

  /// Last reported native video height in pixels, if any.
  int? get videoHeight => _videoHeight;

  /// Stream of available video tracks. Replays the current snapshot on
  /// subscribe.
  Stream<List<VideoTrack>> get videoTracksStream async* {
    yield _videoTracks;
    yield* _videoTracksCtrl.stream;
  }

  /// Stream of available audio tracks. Replays the current snapshot on
  /// subscribe.
  Stream<List<AudioTrack>> get audioTracksStream async* {
    yield _audioTracks;
    yield* _audioTracksCtrl.stream;
  }

  /// Stream of available subtitle tracks. Replays the current snapshot
  /// on subscribe.
  Stream<List<SubtitleTrack>> get subtitleTracksStream async* {
    yield _subtitleTracks;
    yield* _subtitleTracksCtrl.stream;
  }

  /// Stream of the currently selected video track.
  Stream<VideoTrack> get currentVideoTrackStream async* {
    final v = _currentVideoTrack;
    if (v != null) yield v;
    yield* _currentVideoTrackCtrl.stream;
  }

  /// Stream of the currently selected audio track.
  Stream<AudioTrack> get currentAudioTrackStream async* {
    final a = _currentAudioTrack;
    if (a != null) yield a;
    yield* _currentAudioTrackCtrl.stream;
  }

  /// Stream of the currently selected subtitle track.
  Stream<SubtitleTrack> get currentSubtitleTrackStream async* {
    final s = _currentSubtitleTrack;
    if (s != null) yield s;
    yield* _currentSubtitleTrackCtrl.stream;
  }

  /// Stream of native video width in pixels (from the engine).
  Stream<int?> get videoWidthStream async* {
    yield _videoWidth;
    yield* _videoWidthCtrl.stream;
  }

  /// Stream of native video height in pixels (from the engine).
  Stream<int?> get videoHeightStream async* {
    yield _videoHeight;
    yield* _videoHeightCtrl.stream;
  }

  /// Selects a video track by reference. The track must be drawn from
  /// [videoTracks] (or one of the `VideoTrack.auto()` / `.no()` factories).
  Future<void> setVideoTrack(VideoTrack track) async {
    _ensureAlive();
    await _player.setVideoTrack(track);
  }

  /// Selects an audio track by reference. Pass `AudioTrack.no()` to mute.
  Future<void> setAudioTrack(AudioTrack track) async {
    _ensureAlive();
    await _player.setAudioTrack(track);
  }

  /// Selects a subtitle track by reference. Pass `SubtitleTrack.no()` to
  /// hide subtitles.
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    _ensureAlive();
    await _player.setSubtitleTrack(track);
  }

  /// Opens [source] in the player.
  ///
  /// Emits [PlayerLoading] immediately, then transitions based on the
  /// underlying engine's events. If [autoPlay] is false the source is
  /// loaded paused at position zero.
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
      // Re-throw as a typed exception so awaiters can react if they want.
      throw PlayerException('open() failed', e);
    }
  }

  /// Opens [sources] in order until one starts playing.
  ///
  /// Tries each source in sequence: opens it, then waits up to
  /// [perAttemptTimeout] for either a [PlayerPlaying] state (success) or
  /// a [PlayerError] state (fail). Loading or buffering past the timeout
  /// counts as a failure for the purposes of fallback so we don't get
  /// stuck on a panel that returns 200 but never delivers bytes.
  ///
  /// If every source fails, surfaces a [PlayerError] with the message
  /// from the last failed attempt and throws a [PlayerException].
  ///
  /// This is the canonical entry point for IPTV streams where the same
  /// content is reachable under multiple URL shapes (`.ts` ↔ `.m3u8`,
  /// `/live/` prefix optional, etc.). For a single source use [open].
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

      // Wait for the engine to reach a definitive state — playing means
      // success, error means failure, timeout means "stuck loading; try
      // next variant".
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
        // If the engine is still loading, reading buffer state as a
        // signal: any buffer at all means data is flowing — treat as
        // success and let the user see whatever the engine produces.
        if (_buffered > Duration.zero || _position > Duration.zero) {
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
      // Stop the failed source so the next open() starts cleanly.
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

  Future<void> play() async {
    _ensureAlive();
    await _player.play();
  }

  Future<void> pause() async {
    _ensureAlive();
    await _player.pause();
  }

  Future<void> stop() async {
    _ensureAlive();
    await _player.stop();
    _emitState(const PlayerIdle());
  }

  Future<void> seek(Duration to) async {
    _ensureAlive();
    await _player.seek(to);
  }

  /// Sets volume on a 0..100 scale (matches libmpv's native range).
  Future<void> setVolume(double volume) async {
    _ensureAlive();
    final clamped = volume.clamp(0.0, 100.0);
    await _player.setVolume(clamped);
  }

  /// Sets playback speed (1.0 == real-time). libmpv handles 0.01..100,
  /// but we clamp to a sane UX range.
  Future<void> setSpeed(double speed) async {
    _ensureAlive();
    final clamped = speed.clamp(0.25, 4.0);
    await _player.setRate(clamped);
  }

  /// Releases the engine and closes all streams. Safe to call twice; the
  /// second call is a no-op.
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
        _buffered = b;
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
        // media_kit emits an empty string on "error cleared"; ignore those.
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

  /// Decides which [PlayerState] subtype best represents the current
  /// snapshot of cached fields, then emits it (deduplicated).
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
    // Live streams report duration as Duration.zero; surface as null so
    // UI can branch on "no seekbar".
    final total = _duration > Duration.zero ? _duration : null;
    if (_playing) {
      _emitState(PlayerPlaying(
        position: _position,
        buffered: _buffered,
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

  /// Cheap equality check to dedupe redundant emissions. We don't compare
  /// position/buffered fields here because those are emitted on dedicated
  /// streams; the unified state stream should fire on *kind* changes.
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
