import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/auth/cloud_sync_gate.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_mobile/src/shared/sync/cloud_sync_engine.dart';
import 'package:awatv_mobile/src/shared/sync/sync_queue.dart';
import 'package:awatv_mobile/src/shared/sync/sync_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

part 'cloud_sync_providers.g.dart';

/// Singleton FIFO queue shared by every consumer of the sync engine.
@Riverpod(keepAlive: true)
SyncQueue syncQueue(Ref ref) {
  final q = SyncQueue(storage: ref.watch(awatvStorageProvider));
  ref.onDispose(q.close);
  return q;
}

/// The engine itself. Constructed eagerly so it can hold its own
/// subscriptions and timers; activation is gated by [cloudSyncEnginePulse]
/// based on auth + premium state.
///
/// `keepAlive` because the engine owns durable resources (Realtime
/// channel + timers + Hive listeners). Re-creating it per-route would
/// thrash subscriptions and lose pending debounce timers.
@Riverpod(keepAlive: true)
CloudSyncEngine cloudSyncEngine(Ref ref) {
  // No backend configured → engine becomes a no-op stub with a null
  // client. We MUST NOT touch `supa.Supabase.instance` here because
  // accessing the singleton before `Supabase.initialize` ran throws
  // a `LateInitializationError` that surfaces as a Riverpod
  // ProviderException at the root of every screen mount, white-screening
  // the whole app. The engine's methods all guard on `_client == null`.
  if (!Env.hasSupabase) {
    final stub = CloudSyncEngine(
      storage: ref.watch(awatvStorageProvider),
      queue: ref.watch(syncQueueProvider),
      client: null,
    );
    ref.onDispose(stub.dispose);
    return stub;
  }
  final engine = CloudSyncEngine(
    storage: ref.watch(awatvStorageProvider),
    queue: ref.watch(syncQueueProvider),
    client: supa.Supabase.instance.client,
  );
  ref.onDispose(engine.dispose);
  return engine;
}

/// Drives engine lifecycle off the cloud-sync gate.
///
/// Watches [canUseCloudSyncProvider]: when it flips true, calls
/// `engine.activate(userId: …)`; when it flips false, calls
/// `engine.deactivate()`. The provider's value is the engine for
/// callers that want to call `upsertFavorite` directly (e.g. a settings
/// "sync now" button); the side-effect is the activation pulse.
///
/// We use a dedicated provider rather than baking the listen() into
/// [cloudSyncEngine] itself so `keepAlive` semantics stay clean and so
/// tests can stub the activation logic without touching the engine.
@Riverpod(keepAlive: true)
CloudSyncEngine cloudSyncEnginePulse(Ref ref) {
  final engine = ref.watch(cloudSyncEngineProvider);
  final canSync = ref.watch(canUseCloudSyncProvider);
  final auth = ref.watch(authControllerProvider).valueOrNull;

  if (!Env.hasSupabase) {
    // Build never compiled with backend → engine stays disabled.
    return engine;
  }

  if (canSync && auth is AuthSignedIn) {
    // Fire-and-forget activate. Idempotent inside the engine.
    Future.microtask(() => engine.activate(userId: auth.userId));
  } else {
    Future.microtask(engine.deactivate);
  }
  return engine;
}

/// Reactive status stream for the settings row.
///
/// `keepAlive: true` so the underlying Hive listeners stay alive while
/// the user navigates away from settings — the engine still mutates
/// state in the background.
@Riverpod(keepAlive: true)
Stream<SyncStatus> cloudSyncStatus(Ref ref) {
  final engine = ref.watch(cloudSyncEnginePulseProvider);
  return engine.watchStatus();
}

/// Pull list — used by the manage devices screen.
///
/// Intentionally NOT keepAlive: a fresh fetch per visit is the right
/// trade-off (the list is small + the user can pull-to-refresh).
@riverpod
Future<List<DeviceSessionRow>> deviceSessions(Ref ref) async {
  final engine = ref.watch(cloudSyncEnginePulseProvider);
  return engine.listDevices();
}
