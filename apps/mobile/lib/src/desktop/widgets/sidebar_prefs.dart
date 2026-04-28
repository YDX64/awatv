import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hive prefs key for the persisted sidebar collapsed state.
const String _kSidebarCollapsedKey = 'prefs:desktop.sidebar.collapsed';

/// Whether the desktop sidebar is in its collapsed (icon-only, 72dp) form.
///
/// Persisted to the shared `prefs` Hive box so the choice survives
/// restarts. Defaults to `false` (expanded) so first-time users see the
/// labels — same affordance IPTV Expert ships with.
class SidebarCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() {
    final storage = ref.watch(awatvStorageProvider);
    try {
      final raw = storage.prefsBox.get(_kSidebarCollapsedKey);
      if (raw is bool) return raw;
    } on Object {
      // Storage might not be initialised in tests — fall through.
    }
    return false;
  }

  Future<void> toggle() async {
    state = !state;
    final storage = ref.read(awatvStorageProvider);
    try {
      await storage.prefsBox.put(_kSidebarCollapsedKey, state);
    } on Object {
      // Persistence is best-effort.
    }
  }

  Future<void> set(bool collapsed) async {
    if (collapsed == state) return;
    state = collapsed;
    final storage = ref.read(awatvStorageProvider);
    try {
      await storage.prefsBox.put(_kSidebarCollapsedKey, state);
    } on Object {
      // Persistence is best-effort.
    }
  }
}

final sidebarCollapsedProvider =
    NotifierProvider<SidebarCollapsedNotifier, bool>(
  SidebarCollapsedNotifier.new,
);
