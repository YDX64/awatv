import 'package:awatv_core/awatv_core.dart';

/// Direction the user wants to step through the channel list. Used by
/// [pickAdjacentChannel] to decide which way to walk.
enum ChannelStepDirection {
  /// Move to the next channel — typically wired to P+ on a TV remote.
  next,

  /// Move to the previous channel — typically wired to P-.
  previous,
}

/// Pure-Dart helper that picks the channel adjacent to [currentId] inside
/// [pool], wrapping around at the edges. Used by both the player overlay
/// (P+ / P- buttons) and the desktop keyboard shortcuts.
///
/// Returns `null` only when [pool] is empty (which means the user has no
/// live channels to walk through; the caller should ignore the gesture).
///
/// Notes on semantics:
///   * When [currentId] is `null` or not present in [pool], we pick the
///     first ([ChannelStepDirection.next]) or last
///     ([ChannelStepDirection.previous]) channel — same behaviour
///     reference IPTV apps converge on for "P+ from cold".
///   * The list is consumed in the order the caller hands it over. When
///     the channels screen has a category filter active we walk inside
///     the filtered slice; with no filter we walk the full live list.
Channel? pickAdjacentChannel({
  required List<Channel> pool,
  required String? currentId,
  required ChannelStepDirection direction,
}) {
  if (pool.isEmpty) return null;
  if (pool.length == 1) return pool.first;

  final idx = currentId == null
      ? -1
      : pool.indexWhere((Channel c) => c.id == currentId);

  if (idx < 0) {
    return direction == ChannelStepDirection.next ? pool.first : pool.last;
  }

  final next = direction == ChannelStepDirection.next
      ? (idx + 1) % pool.length
      : (idx - 1 + pool.length) % pool.length;
  return pool[next];
}

/// Resolves the "last channel" toggle target. Returns the second-most-
/// recently-visited live channel from [pool] using [historyIds] as the
/// ranking source.
///
/// Skips channels that are no longer in [pool] (deleted from playlist,
/// hidden by a filter, etc.) — the user expects the toggle to "do
/// something useful" even when the history points at a ghost.
///
/// Returns `null` when there's no eligible channel — the caller should
/// flash a brief "Son kanal yok" toast.
Channel? pickLastChannel({
  required List<Channel> pool,
  required List<String> historyIds,
  required String? currentId,
}) {
  if (pool.isEmpty || historyIds.length < 2) return null;
  final byId = <String, Channel>{
    for (final c in pool) c.id: c,
  };
  for (var i = 0; i < historyIds.length; i++) {
    final id = historyIds[i];
    if (id == currentId) continue;
    final candidate = byId[id];
    if (candidate != null) return candidate;
  }
  return null;
}

/// Resolves a "tune to channel N" intent — used by the desktop numeric
/// shortcuts (Numpad 0..9). The first 10 entries in [pool] are reachable
/// as 1..0 on the keypad (Numpad 0 = "10th channel"), matching how a TV
/// remote's number row maps to the user's favourites.
///
/// Returns `null` when [slot] points outside the [pool] — the caller
/// should ignore the gesture without flashing a toast.
Channel? pickByNumericSlot({
  required List<Channel> pool,
  required int slot,
}) {
  if (pool.isEmpty) return null;
  // Numpad 0 maps to position 10 because reading "0" as "ten" matches
  // the way every IPTV remote on the planet labels its number row.
  final idx = slot == 0 ? 9 : slot - 1;
  if (idx < 0 || idx >= pool.length) return null;
  return pool[idx];
}
