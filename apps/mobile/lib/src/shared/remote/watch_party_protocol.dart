/// Wire protocol for the AWAtv Watch Party feature.
///
/// Reuses the same Supabase Realtime broadcast infrastructure as
/// [remote_protocol.dart] but ships its own command sub-hierarchy so
/// the receiver-side player bridge can route remote-control commands
/// without confusing them with party commands.
///
/// Channel name format: `awatv:party:<partyId>` (vs the existing
/// `awatv:remote:<code>` namespace). Same JSON-map encoding strategy.
library;

import 'dart:math';

// =============================================================================
// Commands (any party member -> any other party member)
// =============================================================================

/// Type discriminator embedded in every party-command JSON payload.
const String _kPartyCmdTypeKey = 'type';

/// Concrete party-command tags. Kept as plain string constants so the JSON
/// wire format stays stable across Dart refactors.
abstract class PartyCommandTypes {
  PartyCommandTypes._();
  static const String join = 'party.join';
  static const String leave = 'party.leave';
  static const String sync = 'party.sync';
  static const String chat = 'party.chat';
}

/// Top of the party-command sealed hierarchy. Subtypes encode the
/// payload shape.
sealed class PartyCommand {
  const PartyCommand();

  /// Stable wire tag — never `runtimeType.toString()` because that would
  /// break the protocol the moment the class is renamed.
  String get type;

  Map<String, dynamic> toJson();

  /// Decodes any [PartyCommand] from a Realtime broadcast payload.
  ///
  /// Unknown command types throw [FormatException] — the receiver layer
  /// catches and ignores those so newer clients can ship commands the
  /// older clients do not know about without crashing them.
  // ignore: prefer_constructors_over_static_methods
  static PartyCommand fromJson(Map<String, dynamic> json) {
    final type = json[_kPartyCmdTypeKey];
    if (type is! String) {
      throw const FormatException('PartyCommand: missing type');
    }
    return switch (type) {
      PartyCommandTypes.join => PartyJoinCommand(
          partyId: json['partyId'] as String,
          userId: json['userId'] as String,
          userName: json['userName'] as String,
          isHost: (json['isHost'] as bool?) ?? false,
        ),
      PartyCommandTypes.leave => PartyLeaveCommand(
          userId: json['userId'] as String,
        ),
      PartyCommandTypes.sync => PartySyncCommand(
          userId: json['userId'] as String,
          position: Duration(milliseconds: (json['ms'] as num).toInt()),
          isPlaying: json['isPlaying'] as bool,
          channelId: json['channelId'] as String?,
          isLive: (json['isLive'] as bool?) ?? false,
          fromHost: (json['fromHost'] as bool?) ?? false,
        ),
      PartyCommandTypes.chat => PartyChatCommand(
          userId: json['userId'] as String,
          userName: json['userName'] as String,
          message: json['message'] as String,
          sentAt: DateTime.fromMillisecondsSinceEpoch(
            (json['sentAtMs'] as num).toInt(),
            isUtc: true,
          ),
        ),
      _ => throw FormatException('PartyCommand: unknown type "$type"'),
    };
  }
}

/// Announces a member's arrival into the party. Sent immediately on
/// connect and on each presence-rejoin so late joiners learn about
/// existing members. The host echoes its own join too — there is no
/// "host" distinction in the broadcast layer beyond this flag.
final class PartyJoinCommand extends PartyCommand {
  const PartyJoinCommand({
    required this.partyId,
    required this.userId,
    required this.userName,
    this.isHost = false,
  });

  final String partyId;
  final String userId;
  final String userName;
  final bool isHost;

  @override
  String get type => PartyCommandTypes.join;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        _kPartyCmdTypeKey: type,
        'partyId': partyId,
        'userId': userId,
        'userName': userName,
        'isHost': isHost,
      };
}

/// Announces a member's departure. Best-effort — if the websocket dies
/// without a clean shutdown, the presence timeout in [RemoteChannel]
/// will eventually drop the member after ~30s.
final class PartyLeaveCommand extends PartyCommand {
  const PartyLeaveCommand({required this.userId});

  final String userId;

  @override
  String get type => PartyCommandTypes.leave;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        _kPartyCmdTypeKey: type,
        'userId': userId,
      };
}

/// Playback-state heartbeat. Sent by:
///   * The host every ~1 Hz with the authoritative position.
///   * Any member when their player drifts > 2s from the host position
///     (so the host can see who's lagging).
///   * The host on every state transition (play, pause, seek, channel
///     change) so non-host members can re-sync immediately rather than
///     wait for the next heartbeat.
final class PartySyncCommand extends PartyCommand {
  const PartySyncCommand({
    required this.userId,
    required this.position,
    required this.isPlaying,
    this.channelId,
    this.isLive = false,
    this.fromHost = false,
  });

  final String userId;
  final Duration position;
  final bool isPlaying;

  /// Channel id when the host is watching live TV. Non-host members use
  /// this to switch their own player to the same channel.
  final String? channelId;

  /// Live-channel hint — non-host members use this to know whether the
  /// position payload is meaningful (live streams have no resume point,
  /// so the position is informational only).
  final bool isLive;

  /// True when this snapshot came from the host. Members ignore non-host
  /// snapshots when computing their own re-sync target.
  final bool fromHost;

  @override
  String get type => PartyCommandTypes.sync;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        _kPartyCmdTypeKey: type,
        'userId': userId,
        'ms': position.inMilliseconds,
        'isPlaying': isPlaying,
        if (channelId != null) 'channelId': channelId,
        'isLive': isLive,
        'fromHost': fromHost,
      };
}

/// Chat message broadcast to every party member. Server time is not
/// trusted — we use the sender's wall clock and let the UI render the
/// arrival order it observes (which matches what the user sees).
final class PartyChatCommand extends PartyCommand {
  PartyChatCommand({
    required this.userId,
    required this.userName,
    required this.message,
    DateTime? sentAt,
  }) : sentAt = sentAt ?? DateTime.now().toUtc();

  final String userId;
  final String userName;
  final String message;
  final DateTime sentAt;

  @override
  String get type => PartyCommandTypes.chat;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        _kPartyCmdTypeKey: type,
        'userId': userId,
        'userName': userName,
        'message': message,
        'sentAtMs': sentAt.toUtc().millisecondsSinceEpoch,
      };
}

// =============================================================================
// In-memory party-state aggregates (consumed by UI providers)
// =============================================================================

/// One member of a watch party.
class PartyMember {
  const PartyMember({
    required this.userId,
    required this.userName,
    required this.isHost,
    this.online = true,
    this.lastSeenMs = 0,
    this.lastPositionMs = 0,
    this.isPlaying = false,
  });

  final String userId;
  final String userName;
  final bool isHost;

  /// Whether the member is currently in the websocket session. Falls to
  /// false when we get a [PartyLeaveCommand] or the presence timeout
  /// expires; flips back to true when they rejoin under the same userId.
  final bool online;

  /// Wall-clock millis of the last sync we received from this member.
  final int lastSeenMs;

  /// Last position reported by this member. Used for the "who is
  /// out of sync" indicator on the member chip.
  final int lastPositionMs;

  /// Last play/pause state reported by this member.
  final bool isPlaying;

  PartyMember copyWith({
    bool? online,
    int? lastSeenMs,
    int? lastPositionMs,
    bool? isPlaying,
  }) {
    return PartyMember(
      userId: userId,
      userName: userName,
      isHost: isHost,
      online: online ?? this.online,
      lastSeenMs: lastSeenMs ?? this.lastSeenMs,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}

/// One chat entry, as rendered by the chat panel.
class PartyChat {
  const PartyChat({
    required this.userId,
    required this.userName,
    required this.message,
    required this.sentAt,
  });

  final String userId;
  final String userName;
  final String message;
  final DateTime sentAt;

  /// Whether this message is from the local user — drives the
  /// right-aligned bubble style in the chat list.
  bool isOwn(String localUserId) => userId == localUserId;
}

// =============================================================================
// Party id helpers
// =============================================================================

/// Alphabet used for generated party ids.
///
/// Same set as [pair_code.dart] — dodges letter/digit confusables when
/// users type the id from a phone screen. 8 characters from a 30-symbol
/// set ~= 6.5e11 distinct ids — comfortably collision-free for a
/// short-lived watch party.
const String _kPartyAlphabet = 'ABCDEFGHJKMNPQRTUVWXYZ23456789';

/// Length of the party id surfaced to users.
const int kPartyIdLength = 8;

/// Generates a fresh party id. Call without arguments for production —
/// tests can pass a [Random] seeded with a fixed value for determinism.
String generatePartyId({Random? random}) {
  final rng = random ?? Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < kPartyIdLength; i++) {
    buf.write(_kPartyAlphabet[rng.nextInt(_kPartyAlphabet.length)]);
  }
  return buf.toString();
}

/// Normalises user-typed input. Same semantics as [normalisePairCode] —
/// upper-case, drop whitespace and unsupported characters so users can
/// paste `AB-CD-12-34` and still join.
String normalisePartyId(String raw) {
  final upper = raw.toUpperCase();
  final buf = StringBuffer();
  for (var i = 0; i < upper.length; i++) {
    final ch = upper[i];
    if (_kPartyAlphabet.contains(ch)) buf.write(ch);
  }
  return buf.toString();
}

/// True when [id] could plausibly be a party id we generated.
bool isValidPartyId(String id) {
  if (id.length != kPartyIdLength) return false;
  for (var i = 0; i < id.length; i++) {
    if (!_kPartyAlphabet.contains(id[i])) return false;
  }
  return true;
}

/// Generates a stable random user id for the local device. Persisted in
/// Hive `prefs:watch_party.userId` by the provider so a member that
/// disconnects and rejoins keeps the same identity (and the same
/// "lastSeenMs / lastPositionMs" stats on the host's chip).
String generatePartyUserId({Random? random}) {
  final rng = random ?? Random.secure();
  final buf = StringBuffer('u_');
  for (var i = 0; i < 12; i++) {
    buf.write(_kPartyAlphabet[rng.nextInt(_kPartyAlphabet.length)]);
  }
  return buf.toString();
}
