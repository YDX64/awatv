import 'package:awatv_core/src/models/history_entry.dart';
import 'package:awatv_core/src/storage/awatv_storage.dart';

/// Tracks resume positions and watch history.
class HistoryService {
  HistoryService({required AwatvStorage storage}) : _storage = storage;

  final AwatvStorage _storage;

  Future<void> markPosition(
    String channelId,
    Duration position,
    Duration total, {
    HistoryKind kind = HistoryKind.live,
  }) async {
    final entry = HistoryEntry(
      itemId: channelId,
      kind: kind,
      position: position,
      total: total,
      watchedAt: DateTime.now().toUtc(),
    );
    await _storage.putHistory(entry);
  }

  Future<List<HistoryEntry>> recent({int limit = 50}) {
    return _storage.listHistory(limit: limit);
  }

  /// Resume position if the user is roughly mid-viewing
  /// (>30s in, >30s before end). Returns `null` otherwise.
  Future<Duration?> resumeFor(String channelId) async {
    final entry = await _storage.getHistory(channelId);
    if (entry == null) return null;
    if (entry.total.inSeconds == 0) return entry.position;
    if (entry.position.inSeconds < 30) return null;
    if (entry.total.inSeconds - entry.position.inSeconds < 30) return null;
    return entry.position;
  }
}
