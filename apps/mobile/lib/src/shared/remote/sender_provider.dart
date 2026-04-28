import 'dart:async';

import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/remote/pair_code.dart';
import 'package:awatv_mobile/src/shared/remote/remote_channel.dart';
import 'package:awatv_mobile/src/shared/remote/remote_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of the sender-side session, surfaced to the sender UI.
class SenderSession {
  const SenderSession({
    required this.code,
    required this.connection,
    required this.peerOnline,
    required this.receiverState,
  });

  final String code;
  final RemoteConnectionState connection;

  /// Whether the receiver (TV / desktop) is acknowledging the channel.
  /// While `false`, the remote surface stays disabled to avoid sending
  /// commands into the void.
  final bool peerOnline;

  /// Latest snapshot echoed back by the receiver. Defaults to
  /// [ReceiverState.empty] until the first message arrives.
  final ReceiverState receiverState;

  SenderSession copyWith({
    RemoteConnectionState? connection,
    bool? peerOnline,
    ReceiverState? receiverState,
  }) {
    return SenderSession(
      code: code,
      connection: connection ?? this.connection,
      peerOnline: peerOnline ?? this.peerOnline,
      receiverState: receiverState ?? this.receiverState,
    );
  }
}

/// Reasons the sender session refuses to start.
class SenderSessionUnavailable implements Exception {
  const SenderSessionUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'SenderSessionUnavailable: $reason';
}

/// Controller for the sender-side channel.
///
/// Family-keyed by `code` so the route can pass the parameter through
/// without hand-rolling a state-management layer.
class SenderSessionController
    extends FamilyAsyncNotifier<SenderSession, String> {
  RemoteChannel? _channel;
  StreamSubscription<ReceiverState>? _stateSub;
  StreamSubscription<RemoteConnectionState>? _connSub;
  StreamSubscription<bool>? _peerSub;

  @override
  Future<SenderSession> build(String arg) async {
    if (!Env.hasSupabase) {
      throw const SenderSessionUnavailable(
        'Uzaktan kumanda icin AWAtv hesabi gerekli.',
      );
    }
    final normalised = normalisePairCode(arg);
    if (!isValidPairCode(normalised)) {
      throw SenderSessionUnavailable(
        'Eslestirme kodu gecersiz ($normalised).',
      );
    }

    final channel = await RemoteChannel.connect(
      code: normalised,
      role: RemoteRole.sender,
    );
    _channel = channel;

    ref.onDispose(_cleanup);

    _stateSub = channel.states.listen(_onReceiverState);
    _connSub = channel.connectionStates.listen(_onConn);
    _peerSub = channel.peerPresence.listen(_onPeer);

    return SenderSession(
      code: normalised,
      connection: RemoteConnectionState.connecting,
      peerOnline: false,
      receiverState: ReceiverState.empty,
    );
  }

  /// Pushes a [RemoteCommand] to the receiver. Optimistically applied to
  /// the local snapshot for volume/mute/play-pause so the slider doesn't
  /// jitter while we wait for the receiver echo.
  Future<void> sendCommand(RemoteCommand command) async {
    final ch = _channel;
    if (ch == null) return;
    final current = state.valueOrNull;
    if (current != null) {
      final optimistic = _applyOptimistic(current.receiverState, command);
      if (!identical(optimistic, current.receiverState)) {
        state = AsyncData(current.copyWith(receiverState: optimistic));
      }
    }
    try {
      await ch.sendCommand(command);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('sendCommand failed: $e');
    }
  }

  void _onReceiverState(ReceiverState rstate) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(receiverState: rstate));
  }

  void _onConn(RemoteConnectionState connState) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(connection: connState));
  }

  void _onPeer(bool online) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(peerOnline: online));
  }

  ReceiverState _applyOptimistic(ReceiverState s, RemoteCommand cmd) {
    return switch (cmd) {
      RemoteVolumeCommand(:final volume) => s.copyWith(volume: volume),
      RemoteMuteCommand(:final muted) => s.copyWith(muted: muted),
      RemotePlayPauseCommand() => s.copyWith(
          playback: s.isPlaying
              ? ReceiverPlayback.paused
              : (s.playback == ReceiverPlayback.paused
                  ? ReceiverPlayback.playing
                  : s.playback),
        ),
      RemoteSeekRelativeCommand() ||
      RemoteSeekAbsoluteCommand() ||
      RemoteChannelChangeCommand() ||
      RemoteOpenScreenCommand() =>
        s,
    };
  }

  Future<void> _cleanup() async {
    await _stateSub?.cancel();
    await _connSub?.cancel();
    await _peerSub?.cancel();
    _stateSub = null;
    _connSub = null;
    _peerSub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) await ch.dispose();
  }
}

/// Sender session keyed by pair code. AutoDispose so closing the screen
/// tears the websocket down.
final senderSessionControllerProvider = AsyncNotifierProvider.family<
    SenderSessionController, SenderSession, String>(
  SenderSessionController.new,
);
