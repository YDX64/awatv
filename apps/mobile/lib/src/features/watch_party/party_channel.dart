import 'dart:async';

import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/remote/remote_channel.dart'
    show RemoteConnectionState;
import 'package:awatv_mobile/src/shared/remote/watch_party_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin Supabase Realtime wrapper for the watch-party feature. Mirrors
/// the existing [RemoteChannel] but on a separate `awatv:party:<id>`
/// namespace so members never see remote-control traffic and vice
/// versa.
///
/// Unlike the remote-control channel, every member is "equal" on the
/// wire — the sealed [PartyCommand] hierarchy carries the host bit,
/// not the channel role. So we expose a single [commands] stream and
/// let the controller above decide whether a given command should be
/// applied to the local player or just rendered in the member list.
class PartyChannel {
  PartyChannel._({
    required this.partyId,
    required this.localUserId,
    required RealtimeChannel channel,
  }) : _channel = channel;

  final String partyId;

  /// The locally-generated stable id used to filter our own echoes out
  /// of the inbound stream (Supabase Realtime emits `self` events when
  /// `RealtimeChannelConfig.self` is true).
  final String localUserId;
  final RealtimeChannel _channel;

  static const String _broadcastEventCommand = 'party_command';

  final StreamController<PartyCommand> _commandsCtrl =
      StreamController<PartyCommand>.broadcast();
  final StreamController<RemoteConnectionState> _connCtrl =
      StreamController<RemoteConnectionState>.broadcast();

  RemoteConnectionState _conn = RemoteConnectionState.connecting;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Public surface
  // ---------------------------------------------------------------------------

  /// Stream of inbound commands. Members filter their own echoes out
  /// using the [localUserId] field on each command — we don't drop them
  /// at the wire level because a host whose own join arrives back lets
  /// us confirm the channel actually subscribed.
  Stream<PartyCommand> get commands async* {
    yield* _commandsCtrl.stream;
  }

  /// Connection-state transitions. Replays the latest value on subscribe
  /// so the chip flips immediately when a late listener attaches.
  Stream<RemoteConnectionState> get connectionStates async* {
    yield _conn;
    yield* _connCtrl.stream;
  }

  /// Broadcasts a [PartyCommand] to every member.
  Future<void> sendCommand(PartyCommand command) async {
    if (_disposed) return;
    await _channel.sendBroadcastMessage(
      event: _broadcastEventCommand,
      payload: command.toJson(),
    );
  }

  /// Tears the channel down. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // Best-effort leave broadcast so peers blank our chip immediately
    // instead of waiting for the presence timeout.
    try {
      await _channel.sendBroadcastMessage(
        event: _broadcastEventCommand,
        payload: PartyLeaveCommand(userId: localUserId).toJson(),
      );
    } on Object {
      // already disconnected — nothing to do.
    }

    try {
      await _channel.unsubscribe();
    } on Object catch (e) {
      if (kDebugMode) debugPrint('PartyChannel.dispose unsubscribe: $e');
    }

    try {
      await Supabase.instance.client.removeChannel(_channel);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('PartyChannel.dispose removeChannel: $e');
    }

    await _commandsCtrl.close();
    await _connCtrl.close();
  }

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------

  /// Builds and subscribes a fresh channel for [partyId].
  ///
  /// Throws [StateError] if Supabase is not configured — callers should
  /// guard against that with [Env.hasSupabase].
  static Future<PartyChannel> connect({
    required String partyId,
    required String localUserId,
  }) async {
    if (!Env.hasSupabase) {
      throw StateError('Supabase is not configured; watch parties disabled.');
    }

    final client = Supabase.instance.client;
    final channelName = 'awatv:party:$partyId';
    // `self: true` so a host that joins their own party also sees their
    // own command echoes. Members filter out their own echoes via the
    // userId comparison in [WatchPartySession].
    final realtimeChannel = client.channel(
      channelName,
      opts: const RealtimeChannelConfig(self: true),
    );

    final wrapper = PartyChannel._(
      partyId: partyId,
      localUserId: localUserId,
      channel: realtimeChannel,
    );

    realtimeChannel.onBroadcast(
      event: _broadcastEventCommand,
      callback: wrapper._handleCommand,
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

  void _handleStatusChange(RealtimeSubscribeStatus status, Object? error) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _setConn(RemoteConnectionState.connected);
      case RealtimeSubscribeStatus.closed:
        _setConn(RemoteConnectionState.disconnected);
      case RealtimeSubscribeStatus.channelError:
        if (kDebugMode) debugPrint('PartyChannel error: $error');
        _setConn(RemoteConnectionState.error);
      case RealtimeSubscribeStatus.timedOut:
        _setConn(RemoteConnectionState.reconnecting);
    }
  }

  void _handleCommand(Map<String, dynamic> payload) {
    if (_disposed) return;
    try {
      final cmd = PartyCommand.fromJson(payload);
      _commandsCtrl.add(cmd);
    } on FormatException catch (e) {
      if (kDebugMode) debugPrint('PartyChannel: bad command "$e"');
    }
  }
}
