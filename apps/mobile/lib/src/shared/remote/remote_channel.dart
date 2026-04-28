import 'dart:async';

import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/remote/remote_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Role this device is playing in a remote-control session.
enum RemoteRole { receiver, sender }

/// Connection state surfaced to UI so it can show "waiting / connected /
/// reconnecting / disconnected" without having to introspect Supabase
/// internals.
enum RemoteConnectionState { connecting, connected, reconnecting, disconnected, error }

/// Thin Supabase Realtime wrapper for the remote-control feature.
///
/// Each pair code maps 1:1 to a broadcast channel named
/// `awatv:remote:<code>`. Both sides subscribe to the same channel and
/// listen for opposite-direction broadcast events:
///
///   * Receiver listens for `command` events (decoded into [RemoteCommand]).
///   * Sender listens for `state` events (decoded into [ReceiverState]).
///   * Both can listen for `presence`-style `peer_joined` / `peer_left`
///     pings emitted by the other side on connect/disconnect.
///
/// Auto-reconnect is delegated to the underlying realtime SDK (it keeps a
/// long-lived websocket); we layer a simple presence ping on top so the
/// UI knows when a peer is alive and can blank the now-playing card if the
/// receiver vanishes.
class RemoteChannel {
  RemoteChannel._({
    required this.code,
    required this.role,
    required RealtimeChannel channel,
  }) : _channel = channel;

  final String code;
  final RemoteRole role;
  final RealtimeChannel _channel;

  static const String _broadcastEventCommand = 'command';
  static const String _broadcastEventState = 'state';
  static const String _broadcastEventPeerJoined = 'peer_joined';
  static const String _broadcastEventPeerLeft = 'peer_left';

  final StreamController<RemoteCommand> _commandsCtrl =
      StreamController<RemoteCommand>.broadcast();
  final StreamController<ReceiverState> _statesCtrl =
      StreamController<ReceiverState>.broadcast();
  final StreamController<RemoteConnectionState> _connCtrl =
      StreamController<RemoteConnectionState>.broadcast();
  final StreamController<bool> _peerCtrl =
      StreamController<bool>.broadcast();

  /// Last-known peer presence; replayed to late `peerPresence` listeners.
  bool _peerOnline = false;

  /// Latest connection state; replayed for late listeners.
  RemoteConnectionState _conn = RemoteConnectionState.connecting;

  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Public surface
  // ---------------------------------------------------------------------------

  /// Stream of inbound commands. Receiver-side only — senders will never
  /// see emissions on this stream because we filter by role on send.
  Stream<RemoteCommand> get commands async* {
    yield* _commandsCtrl.stream;
  }

  /// Stream of receiver-state updates. Sender-side only.
  Stream<ReceiverState> get states async* {
    yield* _statesCtrl.stream;
  }

  /// Connection-state transitions. Replays the latest value on subscribe.
  Stream<RemoteConnectionState> get connectionStates async* {
    yield _conn;
    yield* _connCtrl.stream;
  }

  /// Whether the opposite peer (sender from receiver's POV, vice versa)
  /// is currently connected. Replays the latest value on subscribe.
  Stream<bool> get peerPresence async* {
    yield _peerOnline;
    yield* _peerCtrl.stream;
  }

  /// Sends a [RemoteCommand]. Only meaningful from the sender side; on the
  /// receiver this is still allowed (so a receiver could echo commands
  /// for debugging) but would normally not be called.
  Future<void> sendCommand(RemoteCommand command) async {
    if (_disposed) return;
    await _channel.sendBroadcastMessage(
      event: _broadcastEventCommand,
      payload: command.toJson(),
    );
  }

  /// Pushes the receiver's current player snapshot to all listeners.
  /// Called from the receiver's player-bridge ~1 Hz plus on every
  /// significant state transition.
  Future<void> sendState(ReceiverState state) async {
    if (_disposed) return;
    await _channel.sendBroadcastMessage(
      event: _broadcastEventState,
      payload: state.toJson(),
    );
  }

  /// Tears the channel down and closes every internal stream. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // Tell the peer we're leaving so they can blank their UI immediately
    // instead of waiting for the realtime presence timeout.
    try {
      await _channel.sendBroadcastMessage(
        event: _broadcastEventPeerLeft,
        payload: <String, dynamic>{'role': role.name},
      );
    } on Object {
      // Best effort — if we're already disconnected this throws.
    }

    try {
      await _channel.unsubscribe();
    } on Object catch (e) {
      if (kDebugMode) debugPrint('RemoteChannel.dispose unsubscribe: $e');
    }

    try {
      await Supabase.instance.client.removeChannel(_channel);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('RemoteChannel.dispose removeChannel: $e');
    }

    await _commandsCtrl.close();
    await _statesCtrl.close();
    await _connCtrl.close();
    await _peerCtrl.close();
  }

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------

  /// Builds and subscribes a fresh channel for [code].
  ///
  /// Throws [StateError] if Supabase is not configured — callers should
  /// guard against that with [Env.hasSupabase].
  static Future<RemoteChannel> connect({
    required String code,
    required RemoteRole role,
  }) async {
    if (!Env.hasSupabase) {
      throw StateError('Supabase is not configured; remote control disabled.');
    }

    final client = Supabase.instance.client;
    final channelName = 'awatv:remote:$code';
    final realtimeChannel = client.channel(
      channelName,
      opts: const RealtimeChannelConfig(self: false),
    );

    final wrapper = RemoteChannel._(
      code: code,
      role: role,
      channel: realtimeChannel,
    );

    // Wire up broadcast handlers BEFORE subscribing so we don't drop the
    // first event landing between subscribe() and the listener attach.
    realtimeChannel
      ..onBroadcast(
        event: _broadcastEventCommand,
        callback: wrapper._handleCommand,
      )
      ..onBroadcast(
        event: _broadcastEventState,
        callback: wrapper._handleState,
      )
      ..onBroadcast(
        event: _broadcastEventPeerJoined,
        callback: wrapper._handlePeerJoined,
      )
      ..onBroadcast(
        event: _broadcastEventPeerLeft,
        callback: wrapper._handlePeerLeft,
      );

    realtimeChannel.subscribe(wrapper._handleStatusChange);

    return wrapper;
  }

  // ---------------------------------------------------------------------------
  // Internal handlers
  // ---------------------------------------------------------------------------

  void _setConn(RemoteConnectionState next) {
    if (_disposed) return;
    if (_conn == next) return;
    _conn = next;
    _connCtrl.add(next);
  }

  void _setPeer(bool online) {
    if (_disposed) return;
    if (_peerOnline == online) return;
    _peerOnline = online;
    _peerCtrl.add(online);
  }

  void _handleStatusChange(RealtimeSubscribeStatus status, Object? error) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _setConn(RemoteConnectionState.connected);
        // Announce our arrival so the peer can flip its "connected" UI
        // without waiting for the next user-initiated payload.
        unawaited(
          _channel.sendBroadcastMessage(
            event: _broadcastEventPeerJoined,
            payload: <String, dynamic>{'role': role.name},
          ),
        );
      case RealtimeSubscribeStatus.closed:
        _setPeer(false);
        _setConn(RemoteConnectionState.disconnected);
      case RealtimeSubscribeStatus.channelError:
        if (kDebugMode) debugPrint('RemoteChannel error: $error');
        _setConn(RemoteConnectionState.error);
      case RealtimeSubscribeStatus.timedOut:
        _setConn(RemoteConnectionState.reconnecting);
    }
  }

  void _handleCommand(Map<String, dynamic> payload) {
    if (_disposed) return;
    if (role != RemoteRole.receiver) {
      // Senders generally don't care about command events (they sent
      // them) — drop silently.
      return;
    }
    try {
      final cmd = RemoteCommand.fromJson(payload);
      _commandsCtrl.add(cmd);
    } on FormatException catch (e) {
      if (kDebugMode) debugPrint('RemoteChannel: bad command "$e"');
    }
  }

  void _handleState(Map<String, dynamic> payload) {
    if (_disposed) return;
    if (role != RemoteRole.sender) {
      return;
    }
    try {
      final state = ReceiverState.fromJson(payload);
      _statesCtrl.add(state);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('RemoteChannel: bad state "$e"');
    }
  }

  void _handlePeerJoined(Map<String, dynamic> payload) {
    final otherRole = payload['role'] as String?;
    if (otherRole == role.name) return; // own echo if `self: true`
    _setPeer(true);
  }

  void _handlePeerLeft(Map<String, dynamic> payload) {
    final otherRole = payload['role'] as String?;
    if (otherRole == role.name) return;
    _setPeer(false);
  }
}
