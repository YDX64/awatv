import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/notifications/awatv_notifications.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Singleton bridge to `flutter_local_notifications`. Lives behind the
/// [ReminderNotifier] interface so awatv_core stays platform-free.
///
/// Hand-written `Provider` (no @Riverpod codegen) so this file is
/// independent of the build_runner pipeline — the rest of the codebase
/// follows the codegen pattern but adding two new generated files
/// requires running `dart run build_runner build`, which we deliberately
/// don't do in this session.
final awatvNotificationsProvider = Provider<AwatvNotifications>((Ref ref) {
  return AwatvNotifications.instance;
});

/// Reminders service singleton — wired with the platform notifier so
/// "Hatirlat" calls actually schedule an OS notification.
final remindersServiceProvider = Provider<RemindersService>((Ref ref) {
  final notifier = ref.watch(awatvNotificationsProvider);
  return RemindersService(
    storage: ref.watch(awatvStorageProvider),
    notifier: notifier,
  );
});

/// Reactive list of upcoming reminders for the `/reminders` screen.
final upcomingRemindersProvider =
    StreamProvider.autoDispose<List<Reminder>>((Ref ref) async* {
  final svc = ref.watch(remindersServiceProvider);
  // Initial snapshot — mostly so the screen never shows a spinner when
  // the box is empty.
  yield await svc.upcoming();
  // Re-emit on every box change.
  await for (final _ in svc.watch()) {
    yield await svc.upcoming();
  }
});

/// Cheap snapshot of reminder ids — used by EPG tile chrome to render
/// the bell glyph. Computed by mapping the watch stream to a set.
final reminderIdsProvider =
    StreamProvider.autoDispose<Set<String>>((Ref ref) async* {
  final svc = ref.watch(remindersServiceProvider);
  yield (await svc.all()).map((Reminder r) => r.id).toSet();
  await for (final list in svc.watch()) {
    yield list.map((Reminder r) => r.id).toSet();
  }
});

/// Watchlist service singleton.
final watchlistServiceProvider = Provider<WatchlistService>((Ref ref) {
  return WatchlistService(storage: ref.watch(awatvStorageProvider));
});

/// Reactive set of watchlist item ids — used by the heart/clock toggle
/// chrome on detail screens.
final watchlistIdsProvider =
    StreamProvider.autoDispose<Set<String>>((Ref ref) async* {
  final svc = ref.watch(watchlistServiceProvider);
  yield* svc.watch();
});

/// All watchlist entries, optionally filtered by [HistoryKind].
final watchlistEntriesProvider = StreamProvider.autoDispose
    .family<List<WatchlistEntry>, HistoryKind?>(
  (Ref ref, HistoryKind? kind) async* {
    final svc = ref.watch(watchlistServiceProvider);
    yield* svc.watchAll(kind: kind);
  },
);
