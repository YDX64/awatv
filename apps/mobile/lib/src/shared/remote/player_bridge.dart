import 'dart:async';

import 'package:awatv_mobile/src/shared/remote/receiver_provider.dart';
import 'package:awatv_mobile/src/shared/remote/remote_protocol.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Marker payload describing what the local player is currently showing.
///
/// The [PlayerScreen] sets this whenever it boots a controller; the
/// player-bridge then echoes the title/subtitle/artwork back through the
/// channel so the sender's now-playing card stays accurate.
class PlaybackContext {
  const PlaybackContext({
    required this.controller,
    this.title,
    this.subtitle,
    this.artwork,
    this.itemId,
    this.isLive = false,
  });

  final AwaPlayerController controller;
  final String? title;
  final String? subtitle;
  final String? artwork;
  final String? itemId;
  final bool isLive;
}

/// Holds the active player so the bridge can react to remote commands.
///
/// Set by [PlayerScreen] when it boots its controller and cleared on
/// dispose. While `null`, the bridge ignores incoming commands.
class ActivePlayback extends Notifier<PlaybackContext?> {
  @override
  PlaybackContext? build() => null;

  // ignore: use_setters_to_change_properties
  void set(PlaybackContext? ctx) => state = ctx;

  void clear() => state = null;
}

/// Active-playback handle. The player screen writes to this; the bridge
/// reads from it. Kept-alive because the bridge may outlive the screen
/// momentarily during navigation.
final activePlaybackProvider =
    NotifierProvider<ActivePlayback, PlaybackContext?>(ActivePlayback.new);

/// Glue layer; not exposed on the awatv_player package because it pulls
/// in the receiver-session provider from the mobile app.
class RemotePlayerBridge {
  RemotePlayerBridge(this._ref);

  final Ref _ref;

  PlaybackContext? _ctx;
  StreamSubscription<RemoteCommand>? _cmdSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  Timer? _stateThrottle;

  ReceiverState _last = ReceiverState.empty;

  void _onContextChanged(PlaybackContext? ctx) {
    _stateSub?.cancel();
    _posSub?.cancel();
    _stateSub = null;
    _posSub = null;
    _ctx = ctx;
    if (ctx == null) {
      _last = ReceiverState.empty;
      unawaited(_publish(_last));
      return;
    }

    _last = ReceiverState(
      playback: ReceiverPlayback.loading,
      currentTitle: ctx.title,
      currentSubtitle: ctx.subtitle,
      currentArtwork: ctx.artwork,
      currentChannelId: ctx.itemId,
    );
    unawaited(_publish(_last));

    _stateSub = ctx.controller.states.listen(_onPlayerState);
    _posSub = ctx.controller.positions.listen(_onPosition);
  }

  void _ensureCommandSubscription() {
    if (_cmdSub != null) return;
    final ctrl = _ref.read(receiverSessionControllerProvider.notifier);
    _cmdSub = ctrl.commandStream.listen(_onCommand);
  }

  void _dropCommandSubscription() {
    _cmdSub?.cancel();
    _cmdSub = null;
  }

  Future<void> _onCommand(RemoteCommand cmd) async {
    final ctx = _ctx;
    if (ctx == null) return;
    final c = ctx.controller;
    try {
      switch (cmd) {
        case RemotePlayPauseCommand():
          if (_last.isPlaying) {
            await c.pause();
          } else {
            await c.play();
          }
        case RemoteSeekRelativeCommand(:final seconds):
          if (ctx.isLive) break;
          final next = _last.position + Duration(seconds: seconds);
          final total = _last.total;
          final clamped = next < Duration.zero
              ? Duration.zero
              : (total != null && next > total ? total : next);
          await c.seek(clamped);
        case RemoteSeekAbsoluteCommand(:final position):
          if (ctx.isLive) break;
          await c.seek(position);
        case RemoteVolumeCommand(:final volume):
          // AwaPlayerController exposes 0..100; protocol uses 0..1.
          await c.setVolume(volume * 100);
          _last = _last.copyWith(volume: volume);
          unawaited(_publish(_last));
        case RemoteMuteCommand(:final muted):
          // media_kit doesn't expose a dedicated mute flag — fold into
          // the volume control. Restore the previous level on un-mute by
          // re-applying the last-known level.
          if (muted) {
            await c.setVolume(0);
          } else {
            await c.setVolume(_last.volume * 100);
          }
          _last = _last.copyWith(muted: muted);
          unawaited(_publish(_last));
        case RemoteChannelChangeCommand():
          // Future work: route through the channels feature controller.
          break;
        case RemoteOpenScreenCommand():
          // Future work: route through go_router safely (auth guards etc).
          break;
      }
    } on Object catch (e) {
      if (kDebugMode) debugPrint('RemotePlayerBridge command "$cmd" -> $e');
    }
  }

  void _onPlayerState(PlayerState s) {
    final ctx = _ctx;
    if (ctx == null) return;
    ReceiverState next;
    switch (s) {
      case PlayerPlaying(:final position, :final total):
        next = _last.copyWith(
          playback: ReceiverPlayback.playing,
          position: position,
          total: total,
          clearTotal: total == null,
          clearError: true,
        );
      case PlayerPaused(:final position, :final total):
        next = _last.copyWith(
          playback: ReceiverPlayback.paused,
          position: position,
          total: total,
          clearTotal: total == null,
        );
      case PlayerLoading():
        next = _last.copyWith(playback: ReceiverPlayback.loading);
      case PlayerEnded():
        next = _last.copyWith(playback: ReceiverPlayback.ended);
      case PlayerError(:final message):
        next = _last.copyWith(
          playback: ReceiverPlayback.error,
          errorMessage: message,
        );
      case PlayerIdle():
        next = _last.copyWith(playback: ReceiverPlayback.idle);
    }
    if (_isMeaningfullyDifferent(_last, next)) {
      _last = next;
      unawaited(_publish(_last));
    } else {
      _last = next;
    }
  }

  void _onPosition(Duration p) {
    // Throttle position writes to ~1 Hz so we don't flood the channel.
    _stateThrottle ??= Timer(const Duration(seconds: 1), () {
      _stateThrottle = null;
      _last = _last.copyWith(position: p);
      unawaited(_publish(_last));
    });
  }

  Future<void> _publish(ReceiverState rstate) async {
    final session = _ref.read(receiverSessionControllerProvider);
    if (!session.hasValue) return;
    final ctrl = _ref.read(receiverSessionControllerProvider.notifier);
    await ctrl.publishState(rstate);
  }

  bool _isMeaningfullyDifferent(ReceiverState a, ReceiverState b) {
    return a.playback != b.playback ||
        a.errorMessage != b.errorMessage ||
        a.muted != b.muted ||
        a.volume != b.volume ||
        a.currentChannelId != b.currentChannelId;
  }

  void dispose() {
    _stateThrottle?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _cmdSub?.cancel();
  }
}

/// Bridge provider — kept-alive across the app. Listens to changes in
/// both the active-playback context and the receiver session and wires
/// commands / state echoes accordingly.
final remotePlayerBridgeProvider = Provider<RemotePlayerBridge>((Ref ref) {
  final bridge = RemotePlayerBridge(ref);
  ref.onDispose(bridge.dispose);

  ref.listen<PlaybackContext?>(activePlaybackProvider, (
    PlaybackContext? prev,
    PlaybackContext? next,
  ) {
    bridge._onContextChanged(next);
  }, fireImmediately: true);

  ref.listen<AsyncValue<ReceiverSession>>(receiverSessionControllerProvider, (
    AsyncValue<ReceiverSession>? prev,
    AsyncValue<ReceiverSession> next,
  ) {
    if (next.hasValue) {
      bridge._ensureCommandSubscription();
    } else {
      bridge._dropCommandSubscription();
    }
  }, fireImmediately: true);

  return bridge;
});

/// Convenience read so the player screen can ensure the bridge is alive
/// without importing Riverpod's `Ref` directly.
final ensurePlayerBridgeProvider = Provider<RemotePlayerBridge>(
  (Ref ref) => ref.watch(remotePlayerBridgeProvider),
);
