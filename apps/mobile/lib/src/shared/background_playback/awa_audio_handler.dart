import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:awatv_player/awatv_player.dart';

/// Bridges [AwaPlayerController] events to the OS media-session via
/// `audio_service`.
///
/// Why this layer exists:
///   - On iOS the lock-screen "now playing" tile + AirPods double-tap +
///     Control Center playback chip are all driven by `MPNowPlayingInfo`.
///     `audio_service` handles that integration.
///   - On Android the same handler emits a `MediaStyle` foreground-
///     service notification; without it the OS would kill audio after a
///     minute or two of inactivity.
///   - On macOS the menu-bar "now playing" tile reads the same APIs.
///     Lock-screen support there is minimal (no equivalent of CarPlay /
///     Control Center), but the AVAudioSession activation is what keeps
///     decoding alive while the window is hidden.
///
/// The handler owns nothing — the active controller is wired via
/// [bind] each time the player screen boots, and unwired on dispose.
/// We intentionally do *not* try to drive playback from inside this
/// class on idle (the user pressed pause from the lock screen): the
/// command flows back to the controller, which emits a state event
/// that we then re-publish. That keeps a single source of truth.
class AwaAudioHandler extends BaseAudioHandler {
  AwaAudioHandler();

  AwaPlayerController? _controller;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;

  /// Last-known media item; we re-publish on every state change so the
  /// OS notification stays fresh even when the engine has nothing new
  /// to say (e.g. live streams without a duration update).
  MediaItem? _currentItem;

  /// Updates the now-playing metadata. Call from the player screen on
  /// boot and whenever the source changes (e.g. up-next chain).
  void updateNowPlaying({
    required String id,
    required String title,
    String? artist,
    String? album,
    Uri? artUri,
    Duration? duration,
    bool isLive = false,
  }) {
    _currentItem = MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      artUri: artUri,
      duration: duration,
      // For live streams duration is zero — `audio_service` treats null
      // duration as "unknown", which makes the seek bar collapse
      // correctly.
      extras: <String, dynamic>{
        'isLive': isLive,
      },
    );
    mediaItem.add(_currentItem);
  }

  /// Wires this handler to the supplied controller. Pass `null` to
  /// detach (player screen disposed).
  void bind(AwaPlayerController? controller) {
    if (identical(controller, _controller)) return;
    _stateSub?.cancel();
    _positionSub?.cancel();
    _stateSub = null;
    _positionSub = null;
    _controller = controller;

    if (controller == null) {
      // Surface a stopped state so the OS removes its notification chip.
      playbackState.add(
        PlaybackState(
          
        ),
      );
      _currentItem = null;
      return;
    }

    _stateSub = controller.states.listen(_onPlayerState);
    _positionSub = controller.positions.listen((Duration p) {
      // Position updates fire several times a second; we re-emit a
      // playbackState so the lock-screen scrubber tracks. The
      // `updatePosition` field tells iOS / Android the canonical clock
      // so they don't have to interpolate between coarse snapshots.
      _emitState(processing: _lastProcessing, playing: _lastPlaying, position: p);
    });
  }

  AudioProcessingState _lastProcessing = AudioProcessingState.idle;
  bool _lastPlaying = false;

  void _onPlayerState(PlayerState state) {
    switch (state) {
      case PlayerPlaying(:final position):
        _lastProcessing = AudioProcessingState.ready;
        _lastPlaying = true;
        _emitState(
          processing: AudioProcessingState.ready,
          playing: true,
          position: position,
        );
      case PlayerPaused(:final position):
        _lastProcessing = AudioProcessingState.ready;
        _lastPlaying = false;
        _emitState(
          processing: AudioProcessingState.ready,
          playing: false,
          position: position,
        );
      case PlayerLoading():
        _lastProcessing = AudioProcessingState.buffering;
        _emitState(
          processing: AudioProcessingState.buffering,
          playing: _lastPlaying,
          position: playbackState.value.updatePosition,
        );
      case PlayerEnded():
        _lastProcessing = AudioProcessingState.completed;
        _lastPlaying = false;
        _emitState(
          processing: AudioProcessingState.completed,
          playing: false,
          position: playbackState.value.updatePosition,
        );
      case PlayerError():
        _lastProcessing = AudioProcessingState.error;
        _lastPlaying = false;
        _emitState(
          processing: AudioProcessingState.error,
          playing: false,
          position: playbackState.value.updatePosition,
        );
      case PlayerIdle():
        _lastProcessing = AudioProcessingState.idle;
        _lastPlaying = false;
        _emitState(
          processing: AudioProcessingState.idle,
          playing: false,
          position: Duration.zero,
        );
    }
  }

  void _emitState({
    required AudioProcessingState processing,
    required bool playing,
    required Duration position,
  }) {
    final controls = <MediaControl>[
      MediaControl.rewind,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.fastForward,
      MediaControl.stop,
    ];
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        // `androidCompactActionIndices` keeps three icons on the small
        // notification: rewind / play|pause / fast-forward. Stop is
        // available on the expanded notification only.
        androidCompactActionIndices: const <int>[0, 1, 2],
        processingState: processing,
        playing: playing,
        updatePosition: position,
      ),
    );
  }

  // --- Command handlers -------------------------------------------------
  // These fire from the OS (lock-screen press, AirPods double-tap,
  // Android Auto, Bluetooth headset button, etc.). Each delegates back
  // to the controller; the resulting state event re-publishes via
  // `_onPlayerState`, so the OS UI is never out of sync.

  @override
  Future<void> play() async {
    await _controller?.play();
  }

  @override
  Future<void> pause() async {
    await _controller?.pause();
  }

  @override
  Future<void> stop() async {
    await _controller?.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _controller?.seek(position);
  }

  @override
  Future<void> rewind() async {
    final c = _controller;
    if (c == null) return;
    final cur = playbackState.value.updatePosition;
    final next = cur - const Duration(seconds: 10);
    await c.seek(next.isNegative ? Duration.zero : next);
  }

  @override
  Future<void> fastForward() async {
    final c = _controller;
    if (c == null) return;
    final cur = playbackState.value.updatePosition;
    await c.seek(cur + const Duration(seconds: 10));
  }
}
