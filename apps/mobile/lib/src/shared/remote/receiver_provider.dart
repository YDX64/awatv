import 'dart:async';

import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/remote/pair_code.dart';
import 'package:awatv_mobile/src/shared/remote/remote_channel.dart';
import 'package:awatv_mobile/src/shared/remote/remote_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of the receiver-side session, surfaced to the receiver UI.
class ReceiverSession {
  const ReceiverSession({
    required this.code,
    required this.connection,
    required this.peerOnline,
    required this.recentCommands,
  });

  /// The user-facing pair code (also embedded in the QR).
  final String code;

  /// Connection to Supabase Realtime.
  final RemoteConnectionState connection;

  /// Whether the sender (phone) has acknowledged the channel join.
  final bool peerOnline;

  /// Tail of commands received from the sender, newest first, capped at
  /// [ReceiverSessionController.maxRecent]. The receiver UI uses this for
  /// the "recent activity" list.
  final List<RemoteCommand> recentCommands;

  ReceiverSession copyWith({
    String? code,
    RemoteConnectionState? connection,
    bool? peerOnline,
    List<RemoteCommand>? recentCommands,
  }) {
    return ReceiverSession(
      code: code ?? this.code,
      connection: connection ?? this.connection,
      peerOnline: peerOnline ?? this.peerOnline,
      recentCommands: recentCommands ?? this.recentCommands,
    );
  }
}

/// Reasons the receiver session can fail to start. Surfaced via the
/// `AsyncError` of the controller so the UI can render appropriate copy
/// without inspecting exception types.
class ReceiverSessionUnavailable implements Exception {
  const ReceiverSessionUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'ReceiverSessionUnavailable: $reason';
}

/// Controller that owns one receiver-side [RemoteChannel] for the lifetime
/// of the receiver screen.
///
/// Hand-written `AsyncNotifier` rather than codegen so the file is
/// self-contained and `flutter analyze` doesn't depend on running
/// build_runner ahead of time. Same surface as the codegen version.
class ReceiverSessionController extends AsyncNotifier<ReceiverSession> {
  static const int maxRecent = 5;

  RemoteChannel? _channel;
  StreamSubscription<RemoteCommand>? _cmdSub;
  StreamSubscription<RemoteConnectionState>? _connSub;
  StreamSubscription<bool>? _peerSub;

  /// Stream that the player-bridge listens to; gives us a way to fan-out
  /// commands without forcing every consumer to watch the full session
  /// AsyncValue (which rebuilds on every "recent commands" update).
  final StreamController<RemoteCommand> _commandFanout =
      StreamController<RemoteCommand>.broadcast();

  /// Public read-only fan-out used by the player-bridge provider.
  Stream<RemoteCommand> get commandStream => _commandFanout.stream;

  @override
  Future<ReceiverSession> build() async {
    if (!Env.hasSupabase) {
      throw const ReceiverSessionUnavailable(
        'Uzaktan kumanda icin AWAtv hesabi gerekli.',
      );
    }

    final code = generatePairCode();
    final channel = await RemoteChannel.connect(
      code: code,
      role: RemoteRole.receiver,
    );
    _channel = channel;

    ref.onDispose(_cleanup);

    _cmdSub = channel.commands.listen(_onCommand);
    _connSub = channel.connectionStates.listen(_onConn);
    _peerSub = channel.peerPresence.listen(_onPeer);

    return ReceiverSession(
      code: code,
      connection: RemoteConnectionState.connecting,
      peerOnline: false,
      recentCommands: const <RemoteCommand>[],
    );
  }

  /// Pushes a fresh [ReceiverState] to the connected sender, if any.
  Future<void> publishState(ReceiverState rstate) async {
    final ch = _channel;
    if (ch == null) return;
    try {
      await ch.sendState(rstate);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('publishState failed: $e');
    }
  }

  /// User pressed "Stop sharing". Tears the channel down and re-opens the
  /// session with a fresh code on next watch.
  Future<void> stop() async {
    await _cleanup();
    ref.invalidateSelf();
  }

  void _onCommand(RemoteCommand cmd) {
    if (!_commandFanout.isClosed) _commandFanout.add(cmd);
    final current = state.valueOrNull;
    if (current == null) return;
    final next = <RemoteCommand>[cmd, ...current.recentCommands];
    if (next.length > maxRecent) next.removeRange(maxRecent, next.length);
    state = AsyncData(current.copyWith(recentCommands: next));
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

  Future<void> _cleanup() async {
    await _cmdSub?.cancel();
    await _connSub?.cancel();
    await _peerSub?.cancel();
    _cmdSub = null;
    _connSub = null;
    _peerSub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) await ch.dispose();
    if (!_commandFanout.isClosed) await _commandFanout.close();
  }
}

/// Receiver session — kept-alive across rebuilds so a screen rotation
/// doesn't trigger a re-roll of the pair code.
final receiverSessionControllerProvider =
    AsyncNotifierProvider<ReceiverSessionController, ReceiverSession>(
  ReceiverSessionController.new,
);

/// Convenience selector — exposes the live receiver command stream.
/// Returns the controller's broadcast stream, or [Stream.empty] when
/// no receiver session is active. Player wiring listens to this without
/// forcing a hard dependency on the controller's AsyncValue.
final remoteCommandStreamProvider = Provider<Stream<RemoteCommand>>((Ref ref) {
  final session = ref.watch(receiverSessionControllerProvider);
  if (session.valueOrNull == null) {
    return const Stream<RemoteCommand>.empty();
  }
  final ctrl = ref.read(receiverSessionControllerProvider.notifier);
  return ctrl.commandStream;
});
