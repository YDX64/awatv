import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'epg_providers.g.dart';

/// View modes for the live-channels screen.
enum LiveViewMode { list, grid }

/// Hive prefs key for the persisted preference.
const String _kLiveViewModeKey = 'prefs:live.viewMode';

/// User's preferred presentation for the live-channels feature.
///
/// Persisted to the `prefs` Hive box so the choice survives restarts.
/// Default is [LiveViewMode.list] on phones and [LiveViewMode.grid] on
/// tablets/desktop — the screen passes the layout-aware default through
/// `setIfUnset`.
@Riverpod(keepAlive: true)
class LiveViewModePref extends _$LiveViewModePref {
  @override
  LiveViewMode build() {
    final storage = ref.watch(awatvStorageProvider);
    try {
      final raw = storage.prefsBox.get(_kLiveViewModeKey);
      if (raw is String) {
        if (raw == 'grid') return LiveViewMode.grid;
        if (raw == 'list') return LiveViewMode.list;
      }
    } on Object {
      // Storage might not be initialised in tests — fall through.
    }
    return LiveViewMode.list;
  }

  Future<void> set(LiveViewMode mode) async {
    final storage = ref.read(awatvStorageProvider);
    state = mode;
    try {
      await storage.prefsBox.put(_kLiveViewModeKey, mode.name);
    } on Object {
      // Persistence is best-effort.
    }
  }

  /// Apply [mode] only if the user has never explicitly chosen one. Used
  /// the first time the screen renders to pick a sensible default based
  /// on the form factor.
  Future<void> setIfUnset(LiveViewMode mode) async {
    final storage = ref.read(awatvStorageProvider);
    try {
      final raw = storage.prefsBox.get(_kLiveViewModeKey);
      if (raw is String && (raw == 'grid' || raw == 'list')) return;
    } on Object {
      // Treat unreadable as unset.
    }
    await set(mode);
  }
}

/// Wall-clock provider that ticks every minute.
///
/// The EPG grid uses this for the "now" line and the airing-now styling.
/// `keepAlive: true` so multiple consumers (header clock, body line) share
/// the same stream and re-render together.
@Riverpod(keepAlive: true)
Stream<DateTime> epgClock(Ref ref) async* {
  yield DateTime.now();
  // Re-emit at the top of every minute, then every 60s thereafter.
  final now = DateTime.now();
  final nextMinute = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
  ).add(const Duration(minutes: 1));
  await Future<void>.delayed(nextMinute.difference(now));
  yield DateTime.now();
  while (true) {
    await Future<void>.delayed(const Duration(minutes: 1));
    yield DateTime.now();
  }
}

/// Parameters for [epgWindow]. Encoded as a stable string so the family
/// key is hashable.
@immutable
class EpgWindowKey {
  const EpgWindowKey({
    required this.tvgIds,
    this.windowHours = 12,
  });

  final List<String> tvgIds;
  final int windowHours;

  @override
  bool operator ==(Object other) {
    if (other is! EpgWindowKey) return false;
    if (other.windowHours != windowHours) return false;
    if (other.tvgIds.length != tvgIds.length) return false;
    for (var i = 0; i < tvgIds.length; i++) {
      if (other.tvgIds[i] != tvgIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        windowHours,
        Object.hashAll(tvgIds),
      );
}

/// Batched EPG fetch for the grid.
///
/// Returns a map keyed by `tvgId`. Channels with no programmes still
/// appear with an empty list so the grid can render the "EPG yok"
/// placeholder.
@Riverpod()
Future<Map<String, List<EpgProgramme>>> epgWindow(
  Ref ref,
  EpgWindowKey key,
) async {
  final svc = ref.watch(epgServiceProvider);
  return svc.programmesAroundForChannels(
    tvgIds: key.tvgIds,
    window: Duration(hours: key.windowHours),
  );
}
