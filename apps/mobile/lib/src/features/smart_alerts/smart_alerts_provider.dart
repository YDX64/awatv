import 'package:awatv_mobile/src/features/playlists/playlist_providers.dart';
import 'package:awatv_mobile/src/features/smart_alerts/keyword_alert.dart';
import 'package:awatv_mobile/src/features/smart_alerts/smart_alerts_service.dart';
import 'package:awatv_mobile/src/shared/notifications/notifications_provider.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Service singleton — wires Smart Alerts to the existing reminders
/// pipeline so a match produces an OS notification 5 min before air.
///
/// Hand-written `Provider` (no codegen) so we don't need to re-run
/// build_runner in this session.
final smartAlertsServiceProvider = Provider<SmartAlertsService>((Ref ref) {
  final svc = SmartAlertsService(
    storage: ref.watch(awatvStorageProvider),
    reminders: ref.watch(remindersServiceProvider),
    epg: ref.watch(epgServiceProvider),
    favorites: ref.watch(favoritesServiceProvider),
    channelsProvider: () => ref.read(allChannelsProvider.future),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

/// Reactive list of every persisted alert (active + inactive).
final smartAlertsListProvider =
    StreamProvider.autoDispose<List<KeywordAlert>>((Ref ref) async* {
  final svc = ref.watch(smartAlertsServiceProvider);
  yield* svc.watch();
});
