import 'dart:async';

import 'package:awatv_core/awatv_core.dart' show AwatvStorage;
import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/features/watch_party/party_channel.dart';
import 'package:awatv_mobile/src/features/watch_party/watch_party_state.dart';
import 'package:awatv_mobile/src/shared/remote/remote_channel.dart'
    show RemoteConnectionState;
import 'package:awatv_mobile/src/shared/remote/watch_party_protocol.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Identity payload threaded through the party-controller family key —
/// the controller keys off `(partyId, isHost)` so a fresh "Host" tap
/// generates a clean session even if the user previously joined the
/// same party as a member from another browser tab.
class WatchPartyArgs {
  const WatchPartyArgs({
    required this.partyId,
    required this.userName,
    this.isHost = false,
  });

  final String partyId;
  final String userName;
  final bool isHost;

  @override
  bool operator ==(Object other) {
    return other is WatchPartyArgs &&
        other.partyId == partyId &&
        other.userName == userName &&
        other.isHost == isHost;
  }

  @override
  int get hashCode => Object.hash(partyId, userName, isHost);
}

/// Controller that owns one [PartyChannel] for the lifetime of the
/// watch-party screen.
///
/// Hand-written `FamilyAsyncNotifier` rather than codegen — same
/// pattern as [SenderSessionController].
class WatchPartyController
    extends FamilyAsyncNotifier<WatchPartyState, WatchPartyArgs> {
  static const String _userIdPrefsKey = 'watch_party.userId';

  PartyChannel? _channel;
  StreamSubscription<PartyCommand>? _cmdSub;
  StreamSubscription<RemoteConnectionState>? _connSub;
  String? _localUserId;

  /// Stream the party screen subscribes to so it can drive its player's
  /// resync logic without rebuilding the entire AsyncValue every time
  /// the host pings position.
  final StreamController<PartyCommand> _commandFanout =
      StreamController<PartyCommand>.broadcast();

  Stream<PartyCommand> get commandStream => _commandFanout.stream;

  @override
  Future<WatchPartyState> build(WatchPartyArgs arg) async {
    if (!Env.hasSupabase) {
      throw const WatchPartyUnavailable(
        'Watch parti icin AWAtv hesabi gerekli.',
      );
    }
    final partyId = normalisePartyId(arg.partyId);
    if (!isValidPartyId(partyId)) {
      throw WatchPartyUnavailable('Parti kodu gecersiz ($partyId).');
    }

    final userId = await _ensureLocalUserId();
    _localUserId = userId;

    final channel = await PartyChannel.connect(
      partyId: partyId,
      localUserId: userId,
    );
    _channel = channel;
    ref.onDispose(_cleanup);

    _cmdSub = channel.commands.listen(_onCommand);
    _connSub = channel.connectionStates.listen(_onConn);

    // Announce ourselves so existing members can paint the chip.
    unawaited(
      channel.sendCommand(
        PartyJoinCommand(
          partyId: partyId,
          userId: userId,
          userName: arg.userName,
          isHost: arg.isHost,
        ),
      ),
    );

    return WatchPartyState.empty(
      partyId: partyId,
      localUserId: userId,
      localUserName: arg.userName,
      isHost: arg.isHost,
    );
  }

  /// Reads (or generates + persists) the local-device's stable user id
  /// from Hive. Same id is reused across hosts/joiners so a member that
  /// disconnects + rejoins keeps the same chip.
  Future<String> _ensureLocalUserId() async {
    try {
      final storage = ref.read(awatvStorageProvider);
      final box = storage.prefsBox;
      final raw = box.get(_userIdPrefsKey);
      if (raw is String && raw.isNotEmpty) return raw;
      final fresh = generatePartyUserId();
      await box.put(_userIdPrefsKey, fresh);
      return fresh;
    } on Object {
      // If Hive is somehow unavailable, fall back to a per-session id.
      return generatePartyUserId();
    }
  }

  /// Broadcasts a [PartyCommand]. The command is also fed back into the
  /// local handler when `self: true` is set on the channel — so we don't
  /// need a separate optimistic-update path for our own messages.
  Future<void> sendCommand(PartyCommand command) async {
    final ch = _channel;
    if (ch == null) return;
    try {
      await ch.sendCommand(command);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('WatchPartyController.sendCommand failed: $e');
    }
  }

  /// Convenience — pump a chat message into the channel using the
  /// member's own name + cached userId.
  Future<void> sendChat(String message) async {
    final current = state.valueOrNull;
    final userId = _localUserId;
    if (current == null || userId == null) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    await sendCommand(
      PartyChatCommand(
        userId: userId,
        userName: current.localUserName,
        message: trimmed,
      ),
    );
  }

  /// Convenience — pump a sync command. The host's player calls this on
  /// every state transition; non-host members call it only when their
  /// drift estimate changes meaningfully so the wire stays quiet.
  Future<void> publishSync({
    required Duration position,
    required bool isPlaying,
    String? channelId,
    bool isLive = false,
  }) async {
    final current = state.valueOrNull;
    final userId = _localUserId;
    if (current == null || userId == null) return;
    await sendCommand(
      PartySyncCommand(
        userId: userId,
        position: position,
        isPlaying: isPlaying,
        channelId: channelId,
        isLive: isLive,
        fromHost: current.isHost,
      ),
    );
  }

  /// Records the locally-computed drift so the UI can render the
  /// "you are 1.2s ahead" chip without poking another provider.
  void recordDrift(int millis) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.lastDriftMs == millis) return;
    state = AsyncData(current.copyWith(lastDriftMs: millis));
  }

  /// Marks that we just performed an automatic re-sync (so the screen
  /// can suppress the next few drift evaluations to avoid bounce).
  void markResync() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        lastResyncAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      ),
    );
  }

  /// User pressed "Leave party". Tears the channel down.
  Future<void> leave() async {
    final ch = _channel;
    final userId = _localUserId;
    if (ch != null && userId != null) {
      await ch.sendCommand(PartyLeaveCommand(userId: userId));
    }
    await _cleanup();
    ref.invalidateSelf();
  }

  // ---------------------------------------------------------------------------
  // Command handlers
  // ---------------------------------------------------------------------------

  void _onCommand(PartyCommand cmd) {
    if (!_commandFanout.isClosed) _commandFanout.add(cmd);
    final current = state.valueOrNull;
    if (current == null) return;
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;

    switch (cmd) {
      case PartyJoinCommand(
          :final userId,
          :final userName,
          :final isHost,
        ):
        final next = mergeMember(
          current.members,
          PartyMember(
            userId: userId,
            userName: userName,
            isHost: isHost,
          ),
          nowMs: nowMs,
        );
        state = AsyncData(current.copyWith(members: next));
        // Echo our own existence right back so the new joiner learns
        // about us. Best-effort — if the channel is not yet subscribed
        // the broadcast layer will drop it silently.
        if (userId != current.localUserId) {
          unawaited(
            sendCommand(
              PartyJoinCommand(
                partyId: current.partyId,
                userId: current.localUserId,
                userName: current.localUserName,
                isHost: current.isHost,
              ),
            ),
          );
        }
      case PartyLeaveCommand(:final userId):
        final next = dropMember(
          current.members,
          userId,
          localUserId: current.localUserId,
        );
        state = AsyncData(current.copyWith(members: next));
      case PartySyncCommand(
          :final userId,
          :final position,
          :final isPlaying,
          :final fromHost,
        ):
        // Update the member's last-seen position + state.
        final patched = <PartyMember>[
          for (final m in current.members)
            if (m.userId == userId)
              m.copyWith(
                lastSeenMs: nowMs,
                lastPositionMs: position.inMilliseconds,
                isPlaying: isPlaying,
                online: true,
              )
            else
              m,
        ];
        state = AsyncData(
          current.copyWith(
            members: patched,
            lastSync: fromHost ? cmd : current.lastSync,
          ),
        );
      case PartyChatCommand(
          :final userId,
          :final userName,
          :final message,
          :final sentAt,
        ):
        final next = appendChat(
          current.chat,
          PartyChat(
            userId: userId,
            userName: userName,
            message: message,
            sentAt: sentAt,
          ),
        );
        state = AsyncData(current.copyWith(chat: next));
    }
  }

  void _onConn(RemoteConnectionState conn) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(connection: conn));
  }

  Future<void> _cleanup() async {
    await _cmdSub?.cancel();
    await _connSub?.cancel();
    _cmdSub = null;
    _connSub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) await ch.dispose();
    if (!_commandFanout.isClosed) await _commandFanout.close();
  }
}

/// Family-keyed by the full args object so a "Host" attempt and a "Join"
/// attempt against the same partyId still produce distinct controllers
/// (the host bit is sticky for the lifetime of the screen).
final watchPartyControllerProvider = AsyncNotifierProvider.family<
    WatchPartyController, WatchPartyState, WatchPartyArgs>(
  WatchPartyController.new,
);

/// Read-only fan-out — used by the watch-party screen's player to seek
/// the local player into alignment with the host's last sync without
/// having to subscribe to the full state notifier.
final watchPartyCommandStreamProvider =
    Provider.family<Stream<PartyCommand>, WatchPartyArgs>((Ref ref, WatchPartyArgs args) {
  final session = ref.watch(watchPartyControllerProvider(args));
  if (session.valueOrNull == null) {
    return const Stream<PartyCommand>.empty();
  }
  final ctrl = ref.read(watchPartyControllerProvider(args).notifier);
  return ctrl.commandStream;
});

/// Helper to surface the storage handle without forcing every consumer
/// to import the core package directly. We re-export from here so the
/// controller above stays fully self-contained.
typedef WatchPartyStorage = AwatvStorage;
