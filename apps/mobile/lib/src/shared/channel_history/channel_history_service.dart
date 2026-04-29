import 'dart:async';
import 'dart:convert';

import 'package:awatv_core/awatv_core.dart';

/// Tracks the last 50 live channels the user opened. Stored in the
/// Hive `prefs` box as a JSON-encoded list under the key
/// [_kPrefsKey].
///
/// Backbone of the smart channel switcher (P+, P-, Last). All methods
/// are synchronous reads from the in-memory cache; writes pend the
/// Hive `put` but never block the caller.
class ChannelHistoryService {
  ChannelHistoryService({required AwatvStorage storage}) : _storage = storage {
    _hydrateFromDisk();
  }

  static const String _kPrefsKey = 'channels.history';

  /// Hard cap on the persisted list. Above this we drop the oldest
  /// entries — same heuristic IPTV apps converge on so the "history"
  /// stays useful without ballooning the prefs box.
  static const int kMaxEntries = 50;

  final AwatvStorage _storage;
  final List<String> _entries = <String>[];
  final StreamController<List<String>> _ctrl =
      StreamController<List<String>>.broadcast();

  /// Snapshot of the persisted history, newest-first.
  List<String> get entries => List<String>.unmodifiable(_entries);

  /// Most-recent channel id, or `null` when the history is empty.
  String? get currentChannelId => _entries.isEmpty ? null : _entries.first;

  /// Second-most-recent — the one the [last-channel toggle] flips to.
  /// Returns null when the user has only ever watched one channel
  /// (which is what TiviMate falls through to: nothing happens).
  String? get lastChannelId =>
      _entries.length < 2 ? null : _entries[1];

  /// Stream of history snapshots — the player overlay subscribes so the
  /// "Last" button can dim when there's no previous channel to flip to.
  Stream<List<String>> watch() async* {
    yield entries;
    yield* _ctrl.stream;
  }

  /// Records a fresh channel visit. No-ops when [channelId] is already
  /// the current entry (so re-launching the same channel doesn't shift
  /// the "last" pointer to itself).
  Future<void> push(String channelId) async {
    if (channelId.isEmpty) return;
    if (_entries.isNotEmpty && _entries.first == channelId) return;
    _entries.remove(channelId);
    _entries.insert(0, channelId);
    if (_entries.length > kMaxEntries) {
      _entries.removeRange(kMaxEntries, _entries.length);
    }
    _notify();
    await _persist();
  }

  /// Drops [channelId] from the history (used when a deleted-from-source
  /// channel is detected so the "last" toggle doesn't point at a ghost).
  Future<void> remove(String channelId) async {
    final removed = _entries.remove(channelId);
    if (!removed) return;
    _notify();
    await _persist();
  }

  /// Wipes the history. Reachable from settings; defensive enough that
  /// the user can recover from a corrupted prefs box.
  Future<void> clear() async {
    if (_entries.isEmpty) return;
    _entries.clear();
    _notify();
    await _persist();
  }

  Future<void> dispose() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _hydrateFromDisk() {
    try {
      final raw = _storage.prefsBox.get(_kPrefsKey);
      if (raw is String && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _entries
          ..clear()
          ..addAll(list.cast<String>());
      } else if (raw is List) {
        // Some Hive versions return List<dynamic> directly.
        _entries
          ..clear()
          ..addAll(raw.cast<String>());
      }
    } on Object {
      _entries.clear();
    }
  }

  void _notify() {
    if (_ctrl.isClosed) return;
    _ctrl.add(entries);
  }

  Future<void> _persist() async {
    try {
      await _storage.prefsBox.put(_kPrefsKey, jsonEncode(_entries));
    } on Object {
      // Best-effort persistence — losing the history across restarts is
      // recoverable; never let a Hive failure crash playback.
    }
  }
}
