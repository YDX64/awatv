import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:flutter/foundation.dart';

/// One tile in the multi-stream grid.
///
/// Holds the channel metadata + the resolved primary [MediaSource]. The
/// runtime [AwaPlayerController] for the slot is created on-demand by
/// the tile widget so opening + disposing is bounded by widget life
/// rather than session life — the session can stay alive while the user
/// hops in and out of `/multistream` without piling up dead engines.
@immutable
class MultiStreamSlot {
  const MultiStreamSlot({
    required this.channel,
    required this.source,
    this.fallbacks = const <MediaSource>[],
  });

  /// Channel metadata — used for the tile chrome (logo, name, group).
  final Channel channel;

  /// Primary media source. Tile creates a controller against this URL
  /// at attach time; if it fails, the controller walks [fallbacks].
  final MediaSource source;

  /// URL-shape variants for `openWithFallbacks`. Same headers / UA /
  /// referer as [source] — only the URL differs.
  final List<MediaSource> fallbacks;

  /// All sources for `openWithFallbacks(...)` in priority order.
  List<MediaSource> get allSources =>
      <MediaSource>[source, ...fallbacks];

  @override
  bool operator ==(Object other) =>
      other is MultiStreamSlot &&
      other.channel.id == channel.id &&
      other.source.url == source.url;

  @override
  int get hashCode => Object.hash(channel.id, source.url);
}

/// Top-level Riverpod state for the multi-stream session.
///
/// Pure data — every consumer treats slots as immutable so swapping the
/// active tile is a no-op for non-active tiles (no engine restart). The
/// active slot drives audio routing: only the controller at
/// [activeSlotIndex] gets `setVolume(100)`; every other tile is muted.
@immutable
class MultiStreamState {
  const MultiStreamState({
    this.slots = const <MultiStreamSlot>[],
    this.activeSlotIndex = 0,
    this.masterMuted = false,
  });

  /// Up to 4 channels. The grid lays them out 2x2 (landscape) or
  /// vertical-stack (portrait phones).
  final List<MultiStreamSlot> slots;

  /// Index of the currently-audible tile. Always valid when [slots]
  /// is non-empty; clamped to `[0, slots.length-1]` on reads.
  final int activeSlotIndex;

  /// When true, even the active slot is muted. Used by the bottom
  /// bar's master-mute toggle so the user can keep all tiles visible
  /// without audio while watching for a goal.
  final bool masterMuted;

  /// Hard cap on simultaneously-active streams. Beyond 4 the device
  /// runs out of decode capacity on most phones; the UI surfaces a
  /// snack instead of silently dropping the request.
  static const int kMaxSlots = 4;

  bool get isFull => slots.length >= kMaxSlots;

  /// Bounded active index so consumers never have to clamp themselves.
  int get safeActiveIndex {
    if (slots.isEmpty) return 0;
    if (activeSlotIndex < 0) return 0;
    if (activeSlotIndex >= slots.length) return slots.length - 1;
    return activeSlotIndex;
  }

  MultiStreamSlot? get activeSlot {
    if (slots.isEmpty) return null;
    return slots[safeActiveIndex];
  }

  MultiStreamState copyWith({
    List<MultiStreamSlot>? slots,
    int? activeSlotIndex,
    bool? masterMuted,
  }) {
    return MultiStreamState(
      slots: slots ?? this.slots,
      activeSlotIndex: activeSlotIndex ?? this.activeSlotIndex,
      masterMuted: masterMuted ?? this.masterMuted,
    );
  }
}
