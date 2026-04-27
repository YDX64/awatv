import 'dart:async';

import 'package:awatv_core/src/storage/awatv_storage.dart';

/// Per-channel favorites. Stored as a `Box<int>` where the key is the
/// channel id and the value is `1` (set semantics).
class FavoritesService {
  FavoritesService({required AwatvStorage storage}) : _storage = storage;

  final AwatvStorage _storage;
  final StreamController<Set<String>> _ctrl =
      StreamController<Set<String>>.broadcast();

  Future<void> toggle(String channelId) async {
    final box = _storage.favoritesBox;
    if (box.containsKey(channelId)) {
      await box.delete(channelId);
    } else {
      await box.put(channelId, 1);
    }
    _ctrl.add(_currentSet());
  }

  Future<bool> isFavorite(String channelId) async {
    return _storage.favoritesBox.containsKey(channelId);
  }

  Future<Set<String>> all() async => _currentSet();

  Stream<Set<String>> watch() async* {
    yield _currentSet();
    final box = _storage.favoritesBox;
    yield* box.watch().map((_) => _currentSet());
  }

  Set<String> _currentSet() {
    return _storage.favoritesBox.keys.cast<String>().toSet();
  }

  Future<void> dispose() async {
    await _ctrl.close();
  }
}
