import 'package:awatv_mobile/src/shared/channel_history/channel_history_service.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Singleton history service. Boots from Hive on first read so the
/// "last channel" toggle returns the correct id even on a cold launch.
final channelHistoryServiceProvider = Provider<ChannelHistoryService>((Ref ref) {
  final service = ChannelHistoryService(
    storage: ref.watch(awatvStorageProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Reactive history list — newest first. Players watch this so the
/// "Last" button animates between dim/bright as the second-most-recent
/// id appears.
final channelHistoryStreamProvider = StreamProvider<List<String>>((Ref ref) {
  final service = ref.watch(channelHistoryServiceProvider);
  return service.watch();
});

/// Read-only convenience: the second-most-recent channel id, or `null`
/// when fewer than two distinct channels have been visited.
final lastChannelIdProvider = Provider<String?>((Ref ref) {
  final history = ref.watch(channelHistoryStreamProvider).value ??
      ref.read(channelHistoryServiceProvider).entries;
  if (history.length < 2) return null;
  return history[1];
});
