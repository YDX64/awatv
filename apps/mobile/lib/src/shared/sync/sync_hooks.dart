import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_mobile/src/shared/sync/cloud_sync_engine.dart';
import 'package:awatv_mobile/src/shared/sync/cloud_sync_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Helper extensions screens use to perform a *local* mutation and then
/// notify the cloud sync engine in one call.
///
/// Why a separate file instead of editing the core services? The core
/// stays backend-agnostic per AGENT.md zone rules — the engine lives
/// entirely under `apps/mobile/lib/src/shared/sync/`. These helpers are
/// the bridge.
///
/// Pattern: every screen-level call site already had access to a
/// `WidgetRef` (it was reading the service provider anyway), so an
/// extension on `WidgetRef` keeps the call sites clean:
///
/// ```dart
/// await ref.toggleFavoriteSynced(channel.id, kind: HistoryKind.live);
/// ```
extension CloudSyncMutationHooks on WidgetRef {
  /// Toggle a favourite locally and propagate to Supabase.
  ///
  /// Returns the new added/removed state so the caller can update its
  /// own UI without re-reading the box.
  Future<bool> toggleFavoriteSynced(
    String itemId, {
    HistoryKind kind = HistoryKind.live,
  }) async {
    final svc = read(favoritesServiceProvider);
    final wasFav = await svc.isFavorite(itemId);
    await svc.toggle(itemId);
    final isFav = !wasFav;
    // The engine's box listener also fires for this mutation, but we
    // call upsertFavorite explicitly so the kind metadata (live / vod
    // / series) is preserved — the listener can't see kind from a
    // Box<int>.
    final engine = read(cloudSyncEnginePulseProvider);
    await engine.upsertFavorite(itemId, added: isFav, kind: kind);
    return isFav;
  }

  /// Add a playlist source locally and propagate to Supabase.
  Future<PlaylistSource> addPlaylistSourceSynced(PlaylistSource src) async {
    final svc = read(playlistServiceProvider);
    final stored = await svc.add(src);
    final engine = read(cloudSyncEnginePulseProvider);
    await engine.upsertPlaylistSource(stored);
    return stored;
  }

  /// Remove a playlist source locally and propagate to Supabase.
  Future<void> removePlaylistSourceSynced(String sourceId) async {
    final svc = read(playlistServiceProvider);
    await svc.remove(sourceId);
    final engine = read(cloudSyncEnginePulseProvider);
    await engine.removePlaylistSource(sourceId);
  }

  /// Mark a player position locally and propagate (debounced) to
  /// Supabase. The engine debounces history writes so the per-5s
  /// player tick doesn't hammer the network.
  Future<void> markPositionSynced(
    String channelId,
    Duration position,
    Duration total, {
    HistoryKind kind = HistoryKind.live,
  }) async {
    final svc = read(historyServiceProvider);
    await svc.markPosition(channelId, position, total, kind: kind);
    final engine = read(cloudSyncEnginePulseProvider);
    engine.scheduleHistoryUpsert(
      HistoryEntry(
        itemId: channelId,
        kind: kind,
        position: position,
        total: total,
        watchedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Engine accessor — handy for "sync now" buttons / device screens.
  CloudSyncEngine get cloudSyncEngine => read(cloudSyncEnginePulseProvider);
}
