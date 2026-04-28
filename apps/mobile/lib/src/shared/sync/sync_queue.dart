import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:awatv_mobile/src/shared/sync/sync_envelope.dart';
import 'package:hive/hive.dart';

/// Hive-backed FIFO queue of pending [SyncEvent]s.
///
/// Backs the engine when Supabase is unreachable: every push that fails
/// retryably is re-queued with an `attempts` counter; the engine drains
/// the queue with exponential backoff once the network is back.
///
/// Wire format on disk:
///   key   = monotonically incrementing string id (timestamp+counter)
///   value = JSON envelope:
///     {
///       "queued_at":  iso8601,
///       "attempts":   int,
///       "next_at":    iso8601,            // earliest retry time
///       "event":      <SyncEvent.toJson>
///     }
class SyncQueue {
  /// The [storage] argument used to be required so a future migration could
  /// route the queue through [AwatvStorage]; today we open a dedicated Hive
  /// box directly. Kept positional-optional to preserve callers without
  /// triggering an "unused field" analyser warning on the held reference.
  SyncQueue({Object? storage});

  Box<String>? _box;
  final StreamController<int> _depthCtrl = StreamController<int>.broadcast();

  /// Drop events queued more than 7 days ago — they're almost certainly
  /// stale (favorite toggled off then on, history overwritten, …) and
  /// keeping them around just churns the network on reconnect.
  static const Duration _staleAfter = Duration(days: 7);

  /// Hive box name. Distinct from the AwatvStorage core boxes so the
  /// `awatv_core` package never has to know about it.
  static const String _boxName = 'sync:queue';

  /// Open the underlying Hive box. Idempotent — calling more than once
  /// returns the same instance.
  Future<void> ensureOpen() async {
    if (_box != null) return;
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box<String>(_boxName);
    } else {
      _box = await Hive.openBox<String>(_boxName);
    }
    _emitDepth();
  }

  /// Append [event] to the queue. Best-effort — if the box can't open
  /// the call is a no-op rather than throwing into the toggle path.
  Future<void> enqueue(SyncEvent event) async {
    try {
      await ensureOpen();
      final box = _box;
      if (box == null) return;
      final id = _nextKey();
      final wrapper = <String, dynamic>{
        'queued_at': DateTime.now().toUtc().toIso8601String(),
        'attempts': 0,
        'next_at': DateTime.now().toUtc().toIso8601String(),
        'event': event.toJson(),
      };
      await box.put(id, jsonEncode(wrapper));
      _emitDepth();
    } on Object {
      // Persisting the queue is best-effort. The cost of a lost queued
      // event is at most one missed sync — much better than crashing
      // the toggle path.
    }
  }

  /// Drain everything currently due. The caller's [push] returns either
  /// `true` (success → drop the row) or throws — retryable throws bump
  /// `attempts` and bump `next_at` by exponential backoff; non-retryable
  /// throws drop the row immediately and surface upstream.
  Future<void> drain(Future<void> Function(SyncEvent event) push) async {
    await ensureOpen();
    final box = _box;
    if (box == null) return;

    final now = DateTime.now().toUtc();
    final keys = box.keys.toList(growable: false)..sort(_lexCompare);

    for (final key in keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      Map<String, dynamic> wrapper;
      try {
        wrapper = jsonDecode(raw) as Map<String, dynamic>;
      } on Object {
        await box.delete(key);
        continue;
      }

      // Drop stale rows.
      final queuedAt = DateTime.tryParse(wrapper['queued_at'] as String? ?? '');
      if (queuedAt != null && now.difference(queuedAt) > _staleAfter) {
        await box.delete(key);
        continue;
      }

      // Honour backoff.
      final nextAt = DateTime.tryParse(wrapper['next_at'] as String? ?? '');
      if (nextAt != null && nextAt.isAfter(now)) {
        continue;
      }

      final eventJson =
          (wrapper['event'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      final event = SyncEvent.fromJson(eventJson);
      if (event == null) {
        // Unknown variant — drop so it doesn't block the queue.
        await box.delete(key);
        continue;
      }

      try {
        await push(event);
        await box.delete(key);
      } on _NonRetryablePush {
        // Rethrown by the engine for hard failures; drop & continue.
        await box.delete(key);
      } on Object {
        // Bump attempts + backoff and stop draining for now (caller
        // re-runs us on the next reconnect / timer tick).
        final attempts = (wrapper['attempts'] as int? ?? 0) + 1;
        final delay = _backoff(attempts);
        wrapper['attempts'] = attempts;
        wrapper['next_at'] =
            DateTime.now().toUtc().add(delay).toIso8601String();
        await box.put(key, jsonEncode(wrapper));
        _emitDepth();
        return;
      }
    }
    _emitDepth();
  }

  /// Snapshot of the number of pending rows. Used by the settings row
  /// to flip into "askıda" copy when the queue isn't draining.
  Future<int> length() async {
    await ensureOpen();
    return _box?.length ?? 0;
  }

  Stream<int> watchDepth() => _depthCtrl.stream;

  Future<void> close() async {
    await _depthCtrl.close();
  }

  /// Engine helper: signal that a non-retryable push happened and the
  /// surrounding `try` should drop the row.
  static Object nonRetryable(SyncEvent event, Object cause) {
    return _NonRetryablePush(event, cause);
  }

  // -- internal --------------------------------------------------------------

  int _seq = 0;

  String _nextKey() {
    final ts = DateTime.now().toUtc().microsecondsSinceEpoch;
    final n = _seq++;
    // Lex-sortable pad — 10^16 microseconds covers ~317 years.
    return '${ts.toString().padLeft(20, '0')}-${n.toString().padLeft(6, '0')}';
  }

  int _lexCompare(dynamic a, dynamic b) =>
      (a as String).compareTo(b as String);

  Duration _backoff(int attempts) {
    // 2s * 2^(attempts-1) capped at 5min, with a tiny jitter.
    final base = math.min(300, 2 * math.pow(2, attempts - 1).toInt());
    final jitter = (attempts * 113) % 1000;
    return Duration(milliseconds: base * 1000 + jitter);
  }

  void _emitDepth() {
    if (_depthCtrl.isClosed) return;
    _depthCtrl.add(_box?.length ?? 0);
  }
}

/// Sentinel thrown by the engine to mark a push failure as terminal.
class _NonRetryablePush implements Exception {
  const _NonRetryablePush(this.event, this.cause);
  final SyncEvent event;
  final Object cause;

  @override
  String toString() => 'NonRetryablePush(${event.runtimeType}): $cause';
}
