import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_scoped_storage.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Profile-scoped favourites service. Rebuilds whenever the active
/// profile id changes — the previous instance disposes via the Hive
/// stream controller and any UI watching `favouritesWatchProvider` gets
/// re-subscribed automatically.
///
/// We don't override the existing `favoritesServiceProvider` because the
/// default-profile path (the only one for users upgrading from a
/// pre-profiles build) uses the legacy un-scoped favourites box — same
/// box the cloud sync engine already listens to.
final profileFavoritesServiceProvider =
    Provider<ProfileFavoritesService>((Ref ref) {
  final activeId =
      ref.watch(activeProfileIdProvider).valueOrNull ??
          ProfileScopedStorage.defaultProfileId;
  final svc = ProfileFavoritesService(profileId: activeId);
  ref.onDispose(svc.dispose);
  return svc;
});

/// Live set of favourite ids for the active profile.
final profileFavoritesProvider = StreamProvider<Set<String>>((Ref ref) {
  final svc = ref.watch(profileFavoritesServiceProvider);
  return svc.watch();
});

/// Profile-scoped history service.
final profileHistoryServiceProvider =
    Provider<ProfileHistoryService>((Ref ref) {
  final activeId =
      ref.watch(activeProfileIdProvider).valueOrNull ??
          ProfileScopedStorage.defaultProfileId;
  return ProfileHistoryService(profileId: activeId);
});

/// Recent watch entries for the active profile. Cheap enough that
/// callers can re-watch this on every screen build.
final profileRecentHistoryProvider =
    FutureProvider<List<HistoryEntry>>((Ref ref) async {
  final svc = ref.watch(profileHistoryServiceProvider);
  return svc.recent();
});

/// Invalidates the global `favoritesServiceProvider` /
/// `historyServiceProvider` whenever the active profile id changes.
///
/// This is a no-op when the active profile is the legacy default
/// (its box is still the un-scoped `favorites` / `history` Hive box),
/// but invalidating gives any in-flight `StreamProvider` watcher a
/// chance to drop a stale subscription before re-attaching to the
/// (potentially different) box. Mounted once from `AwaTvApp.build`
/// via `ref.watch`.
final profileSyncListenerProvider = Provider<void>((Ref ref) {
  ref.listen<AsyncValue<String>>(activeProfileIdProvider, (previous, next) {
    final prevId = previous?.valueOrNull;
    final nextId = next.valueOrNull;
    if (prevId == nextId) return;
    ref
      ..invalidate(favoritesServiceProvider)
      ..invalidate(historyServiceProvider);
  });
});
