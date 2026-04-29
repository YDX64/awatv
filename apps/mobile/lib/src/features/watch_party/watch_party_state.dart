import 'package:awatv_mobile/src/features/watch_party/watch_party_controller.dart' show WatchPartyController;
import 'package:awatv_mobile/src/shared/remote/remote_channel.dart'
    show RemoteConnectionState;
import 'package:awatv_mobile/src/shared/remote/watch_party_protocol.dart';

/// Live snapshot of a watch-party session. Surfaced to the UI through
/// [WatchPartyController.state]; the chat panel and member bar rebuild
/// off the lists in here.
class WatchPartyState {
  const WatchPartyState({
    required this.partyId,
    required this.localUserId,
    required this.localUserName,
    required this.isHost,
    required this.connection,
    required this.members,
    required this.chat,
    this.lastSync,
    this.lastDriftMs = 0,
    this.lastResyncAtMs = 0,
  });

  /// Empty session — used as the initial value before [WatchPartyController.build]
  /// finishes connecting.
  factory WatchPartyState.empty({
    required String partyId,
    required String localUserId,
    required String localUserName,
    required bool isHost,
  }) {
    return WatchPartyState(
      partyId: partyId,
      localUserId: localUserId,
      localUserName: localUserName,
      isHost: isHost,
      connection: RemoteConnectionState.connecting,
      members: <PartyMember>[
        PartyMember(
          userId: localUserId,
          userName: localUserName,
          isHost: isHost,
          lastSeenMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      ],
      chat: const <PartyChat>[],
    );
  }

  final String partyId;
  final String localUserId;
  final String localUserName;
  final bool isHost;
  final RemoteConnectionState connection;
  final List<PartyMember> members;
  final List<PartyChat> chat;

  /// Latest sync command received from the host. Non-host members read
  /// this to decide whether to seek their own player; the host writes
  /// it on every state change so the UI can display "host: BBC One,
  /// 14:23" without having to re-derive from the members list.
  final PartySyncCommand? lastSync;

  /// Last computed drift between the local position and the host
  /// position, in millis. Renders as a small chip ("+1.2s ahead") on
  /// the host row when non-zero.
  final int lastDriftMs;

  /// Wall-clock millis of the last automatic re-sync we triggered.
  /// Used to avoid back-to-back seeks when the network is flapping.
  final int lastResyncAtMs;

  /// Convenience — the [PartyMember] entry for the host, if any. Used
  /// by the chat panel to badge the host's name with a star.
  PartyMember? get host {
    for (final m in members) {
      if (m.isHost) return m;
    }
    return null;
  }

  /// Convenience — every member except the local user. The members bar
  /// uses this to render only "the other people in the party".
  List<PartyMember> get others {
    return <PartyMember>[
      for (final m in members)
        if (m.userId != localUserId) m,
    ];
  }

  /// Whether the channel is fully connected and the host is alive.
  /// The play/pause/seek controls bind to this.
  bool get canControl => connection == RemoteConnectionState.connected;

  WatchPartyState copyWith({
    RemoteConnectionState? connection,
    List<PartyMember>? members,
    List<PartyChat>? chat,
    PartySyncCommand? lastSync,
    int? lastDriftMs,
    int? lastResyncAtMs,
  }) {
    return WatchPartyState(
      partyId: partyId,
      localUserId: localUserId,
      localUserName: localUserName,
      isHost: isHost,
      connection: connection ?? this.connection,
      members: members ?? this.members,
      chat: chat ?? this.chat,
      lastSync: lastSync ?? this.lastSync,
      lastDriftMs: lastDriftMs ?? this.lastDriftMs,
      lastResyncAtMs: lastResyncAtMs ?? this.lastResyncAtMs,
    );
  }
}

/// Reasons the watch-party session refuses to start.
class WatchPartyUnavailable implements Exception {
  const WatchPartyUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'WatchPartyUnavailable: $reason';
}

/// Helper used by the controller to merge a join/sync update into the
/// existing members list. Returns a fresh list so widget rebuilds are
/// driven cleanly.
List<PartyMember> mergeMember(
  List<PartyMember> current,
  PartyMember next, {
  required int nowMs,
}) {
  final out = <PartyMember>[];
  var found = false;
  for (final m in current) {
    if (m.userId == next.userId) {
      out.add(
        next.copyWith(
          lastSeenMs: nowMs,
        ),
      );
      found = true;
    } else {
      out.add(m);
    }
  }
  if (!found) {
    out.add(next.copyWith(lastSeenMs: nowMs));
  }
  return out;
}

/// Drops a member from [current] (used on [PartyLeaveCommand]). We
/// never actually remove ourselves — the local user always renders in
/// the members bar even after leaving the party so the UI doesn't
/// flicker during the disconnect frame.
List<PartyMember> dropMember(
  List<PartyMember> current,
  String userId, {
  required String localUserId,
}) {
  if (userId == localUserId) {
    // Mark ourselves offline rather than removing — keeps the bar
    // visually stable through the dispose call.
    return <PartyMember>[
      for (final m in current)
        if (m.userId == localUserId) m.copyWith(online: false) else m,
    ];
  }
  return <PartyMember>[
    for (final m in current)
      if (m.userId != userId) m else m.copyWith(online: false),
  ];
}

/// Caps the chat list at [max] entries so the scroll buffer stays
/// bounded over a long party.
List<PartyChat> appendChat(
  List<PartyChat> current,
  PartyChat next, {
  int max = 200,
}) {
  final out = <PartyChat>[...current, next];
  if (out.length > max) {
    out.removeRange(0, out.length - max);
  }
  return out;
}
