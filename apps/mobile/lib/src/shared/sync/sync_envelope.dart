import 'package:awatv_core/awatv_core.dart';

/// Outbound mutations the engine knows how to push to Supabase.
///
/// Sealed so the engine `switch`-dispatches on the variant rather than
/// reflecting on a `kind` string. Every variant carries the live
/// `userId` (the engine refuses to push events for a different user
/// than the currently signed-in one) and an `updatedAt` timestamp that
/// drives last-writer-wins conflict resolution against the server row.
///
/// JSON shape is intentionally manual (not freezed): the queue persists
/// envelopes to Hive across restarts and we want a stable on-disk
/// representation that's resilient to model-class refactors. The
/// `kind` discriminator is the contract — never rename a value.
sealed class SyncEvent {
  const SyncEvent({required this.userId, required this.updatedAt});

  final String userId;
  final DateTime updatedAt;

  Map<String, dynamic> toJson();

  /// Reconstruct from a queue-persisted JSON blob. Returns `null` for
  /// unknown kinds so an old build that wrote a future variant can be
  /// drained without crashing.
  static SyncEvent? fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    switch (kind) {
      case 'favorite_upserted':
        return FavoriteUpserted._fromJson(json);
      case 'favorite_removed':
        return FavoriteRemoved._fromJson(json);
      case 'history_upserted':
        return HistoryUpserted._fromJson(json);
      case 'history_removed':
        return HistoryRemoved._fromJson(json);
      case 'playlist_source_upserted':
        return PlaylistSourceUpserted._fromJson(json);
      case 'playlist_source_removed':
        return PlaylistSourceRemoved._fromJson(json);
      case 'device_session_upserted':
        return DeviceSessionUpserted._fromJson(json);
      case 'device_session_removed':
        return DeviceSessionRemoved._fromJson(json);
      default:
        return null;
    }
  }
}

/// `favorites` row written or refreshed.
final class FavoriteUpserted extends SyncEvent {
  const FavoriteUpserted({
    required super.userId,
    required super.updatedAt,
    required this.itemId,
    required this.itemKind,
  });

  factory FavoriteUpserted._fromJson(Map<String, dynamic> json) {
    return FavoriteUpserted(
      userId: json['user_id'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      itemId: json['item_id'] as String,
      itemKind: _parseFavKind(json['item_kind'] as String?),
    );
  }

  final String itemId;
  final FavoriteItemKind itemKind;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': 'favorite_upserted',
        'user_id': userId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'item_id': itemId,
        'item_kind': itemKind.wire,
      };
}

/// `favorites` row deleted by the local client.
final class FavoriteRemoved extends SyncEvent {
  const FavoriteRemoved({
    required super.userId,
    required super.updatedAt,
    required this.itemId,
  });

  factory FavoriteRemoved._fromJson(Map<String, dynamic> json) {
    return FavoriteRemoved(
      userId: json['user_id'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      itemId: json['item_id'] as String,
    );
  }

  final String itemId;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': 'favorite_removed',
        'user_id': userId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'item_id': itemId,
      };
}

/// `watch_history` row updated.
final class HistoryUpserted extends SyncEvent {
  const HistoryUpserted({
    required super.userId,
    required super.updatedAt,
    required this.entry,
  });

  factory HistoryUpserted._fromJson(Map<String, dynamic> json) {
    return HistoryUpserted(
      userId: json['user_id'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      entry: HistoryEntry.fromJson(
        (json['entry'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  final HistoryEntry entry;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': 'history_upserted',
        'user_id': userId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'entry': entry.toJson(),
      };
}

/// `watch_history` row deleted by the local client.
final class HistoryRemoved extends SyncEvent {
  const HistoryRemoved({
    required super.userId,
    required super.updatedAt,
    required this.itemId,
  });

  factory HistoryRemoved._fromJson(Map<String, dynamic> json) {
    return HistoryRemoved(
      userId: json['user_id'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      itemId: json['item_id'] as String,
    );
  }

  final String itemId;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': 'history_removed',
        'user_id': userId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'item_id': itemId,
      };
}

/// `playlist_sources` row added or renamed.
///
/// Wire payload deliberately strips URL/credentials — the schema doesn't
/// store them and they should never leave the device.
final class PlaylistSourceUpserted extends SyncEvent {
  const PlaylistSourceUpserted({
    required super.userId,
    required super.updatedAt,
    required this.clientId,
    required this.name,
    required this.kind,
    required this.addedAt,
    this.lastSyncAt,
  });

  factory PlaylistSourceUpserted._fromJson(Map<String, dynamic> json) {
    return PlaylistSourceUpserted(
      userId: json['user_id'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      clientId: json['client_id'] as String,
      name: json['name'] as String,
      kind: _parsePlaylistKind(json['plkind'] as String?),
      addedAt: DateTime.parse(json['added_at'] as String),
      lastSyncAt: json['last_sync_at'] is String
          ? DateTime.tryParse(json['last_sync_at'] as String)
          : null,
    );
  }

  final String clientId;
  final String name;
  final PlaylistKind kind;
  final DateTime addedAt;
  final DateTime? lastSyncAt;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': 'playlist_source_upserted',
        'user_id': userId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'client_id': clientId,
        'name': name,
        'plkind': kind.name,
        'added_at': addedAt.toUtc().toIso8601String(),
        'last_sync_at': lastSyncAt?.toUtc().toIso8601String(),
      };
}

/// `playlist_sources` row deleted by the local client.
final class PlaylistSourceRemoved extends SyncEvent {
  const PlaylistSourceRemoved({
    required super.userId,
    required super.updatedAt,
    required this.clientId,
  });

  factory PlaylistSourceRemoved._fromJson(Map<String, dynamic> json) {
    return PlaylistSourceRemoved(
      userId: json['user_id'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      clientId: json['client_id'] as String,
    );
  }

  final String clientId;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': 'playlist_source_removed',
        'user_id': userId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'client_id': clientId,
      };
}

/// Heartbeat / rename for the `device_sessions` row that represents this
/// install. The engine stamps one of these on activate and on resume.
final class DeviceSessionUpserted extends SyncEvent {
  const DeviceSessionUpserted({
    required super.userId,
    required super.updatedAt,
    required this.deviceId,
    required this.deviceKind,
    required this.platform,
    this.userAgent,
  });

  factory DeviceSessionUpserted._fromJson(Map<String, dynamic> json) {
    return DeviceSessionUpserted(
      userId: json['user_id'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deviceId: json['device_id'] as String,
      deviceKind: _parseDeviceKind(json['device_kind'] as String?),
      platform: json['platform'] as String,
      userAgent: json['user_agent'] as String?,
    );
  }

  final String deviceId;
  final DeviceKind deviceKind;
  final String platform;
  final String? userAgent;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': 'device_session_upserted',
        'user_id': userId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'device_id': deviceId,
        'device_kind': deviceKind.wire,
        'platform': platform,
        'user_agent': userAgent,
      };
}

/// Remote-revoke / sign-out request for a specific device row.
final class DeviceSessionRemoved extends SyncEvent {
  const DeviceSessionRemoved({
    required super.userId,
    required super.updatedAt,
    required this.rowId,
  });

  factory DeviceSessionRemoved._fromJson(Map<String, dynamic> json) {
    return DeviceSessionRemoved(
      userId: json['user_id'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      rowId: json['row_id'] as String,
    );
  }

  /// Server-side `device_sessions.id` (uuid). We use the row id rather
  /// than the client `device_id` so a sender can revoke a particular
  /// row even when there are stale duplicates.
  final String rowId;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': 'device_session_removed',
        'user_id': userId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'row_id': rowId,
      };
}

// ---------------------------------------------------------------------------
// Helper enums + parsers
// ---------------------------------------------------------------------------

/// Mirrors the server `favorites.item_kind` check constraint.
///
/// Maps `HistoryKind` 1:1 — the kinds line up by design so a single
/// channel id can be both a watch_history row and a favorites row of
/// the same kind.
enum FavoriteItemKind {
  live('live'),
  vod('vod'),
  series('series');

  const FavoriteItemKind(this.wire);
  final String wire;

  static FavoriteItemKind fromHistoryKind(HistoryKind k) => switch (k) {
        HistoryKind.live => FavoriteItemKind.live,
        HistoryKind.vod => FavoriteItemKind.vod,
        HistoryKind.series => FavoriteItemKind.series,
      };
}

FavoriteItemKind _parseFavKind(String? raw) {
  return FavoriteItemKind.values.firstWhere(
    (k) => k.wire == raw,
    orElse: () => FavoriteItemKind.live,
  );
}

PlaylistKind _parsePlaylistKind(String? raw) {
  return PlaylistKind.values.firstWhere(
    (k) => k.name == raw,
    orElse: () => PlaylistKind.m3u,
  );
}

/// Mirrors the server `device_sessions.device_kind` check constraint.
enum DeviceKind {
  phone('phone'),
  tablet('tablet'),
  tv('tv'),
  desktop('desktop'),
  web('web');

  const DeviceKind(this.wire);
  final String wire;
}

DeviceKind _parseDeviceKind(String? raw) {
  return DeviceKind.values.firstWhere(
    (k) => k.wire == raw,
    orElse: () => DeviceKind.phone,
  );
}
