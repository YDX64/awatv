/// Runtime status of the cloud sync engine.
///
/// Sealed so the settings row and any future UI surface can pattern
/// match without writing a fall-through default that masks a new
/// variant. The settings copy is computed centrally on the engine side
/// — UI just renders the [statusLabel] / [detailLabel] returned by
/// [SyncStatus.localized] (Turkish-first, because user-facing chat is
/// Turkish per CLAUDE.md house rules).
sealed class SyncStatus {
  const SyncStatus();

  /// Convenience: short Turkish status string for the settings row.
  String localized() => switch (this) {
        SyncDisabled() =>
          'Senkron askıda — premium ve oturum açık olmalı',
        SyncBootstrapping() => 'Senkron başlatılıyor…',
        SyncIdle(:final lastSyncAt) =>
          'Senkron — son güncelleme: ${_relativeTr(lastSyncAt)}',
        SyncPushing() => 'Senkron — yükleniyor…',
        SyncPulling() => 'Senkron — indiriliyor…',
        SyncOffline() => 'Bağlanılamıyor',
        SyncFailed(:final message) => 'Senkron hatası: $message',
      };

  /// Whether the engine is actively connected and pushing updates.
  bool get isActive => switch (this) {
        SyncIdle() || SyncPulling() || SyncPushing() => true,
        _ => false,
      };
}

/// Engine inactive — typically because the user is signed out or not
/// premium, or because the build was compiled without Supabase.
final class SyncDisabled extends SyncStatus {
  const SyncDisabled([this.reason]);
  final String? reason;
}

/// Engine just activated; running pull-down + push-up.
final class SyncBootstrapping extends SyncStatus {
  const SyncBootstrapping();
}

/// Caught up. [lastSyncAt] is the most recent successful round-trip.
final class SyncIdle extends SyncStatus {
  const SyncIdle({required this.lastSyncAt});
  final DateTime lastSyncAt;
}

/// Currently pushing pending events.
final class SyncPushing extends SyncStatus {
  const SyncPushing();
}

/// Currently pulling remote rows.
final class SyncPulling extends SyncStatus {
  const SyncPulling();
}

/// Network unreachable. The queue will retry on reconnect.
final class SyncOffline extends SyncStatus {
  const SyncOffline();
}

/// A non-retryable error tripped the engine. UI should expose a "retry"
/// affordance that calls `cloudSyncEngine.activate()` again.
final class SyncFailed extends SyncStatus {
  const SyncFailed(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// Internal: tiny relative-time formatter (Turkish-first to match settings).
// ---------------------------------------------------------------------------

String _relativeTr(DateTime when) {
  final now = DateTime.now().toUtc();
  final delta = now.difference(when.toUtc());
  if (delta.inSeconds < 30) return 'az önce';
  if (delta.inMinutes < 1) return '${delta.inSeconds} saniye önce';
  if (delta.inMinutes == 1) return '1 dakika önce';
  if (delta.inMinutes < 60) return '${delta.inMinutes} dakika önce';
  if (delta.inHours == 1) return '1 saat önce';
  if (delta.inHours < 24) return '${delta.inHours} saat önce';
  if (delta.inDays == 1) return 'dün';
  return '${delta.inDays} gün önce';
}
