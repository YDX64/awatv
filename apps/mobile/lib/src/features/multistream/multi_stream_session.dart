import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/multistream/multi_stream_state.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'multi_stream_session.g.dart';

/// Owns the multi-stream session.
///
/// Kept-alive across route transitions so users can navigate from
/// `/live` → tile long-press "Coklu izle" → `/multistream` without
/// losing the existing slot list. Disposed only when the user taps
/// [clear] (the bottom-bar exit) or the app shuts down.
///
/// The controller is intentionally lightweight — no [AwaPlayerController]
/// instances live here; the grid widget creates one per visible tile and
/// disposes them when the tile unmounts. This keeps engine cost bounded
/// to "what's currently visible" rather than "what's ever been added".
@Riverpod(keepAlive: true)
class MultiStreamSession extends _$MultiStreamSession {
  @override
  MultiStreamState build() => const MultiStreamState();

  /// Adds [channel] to the session.
  ///
  /// No-ops when the channel is already present (matched by id) or when
  /// the session is full. Returns the index of the newly-added (or
  /// already-present) slot so callers can route the user to that tile.
  ///
  /// The first added channel becomes the active slot automatically;
  /// subsequent channels start muted.
  int? addChannel(Channel channel) {
    final existing = state.slots.indexWhere(
      (MultiStreamSlot s) => s.channel.id == channel.id,
    );
    if (existing != -1) {
      // Already in the grid — surface its index so the caller can
      // highlight it instead of silently doing nothing.
      return existing;
    }
    if (state.isFull) return null;

    final urls = streamUrlVariants(channel.streamUrl).map(proxify).toList();
    final ua = channel.extras['http-user-agent'] ??
        channel.extras['user-agent'];
    final referer = channel.extras['http-referrer'] ??
        channel.extras['referer'] ??
        channel.extras['Referer'];
    final headers = <String, String>{
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
    };
    final variants = MediaSource.variants(
      urls,
      title: channel.name,
      userAgent: ua,
      headers: headers.isEmpty ? null : headers,
    );
    final primary = variants.isEmpty
        ? MediaSource(
            url: proxify(channel.streamUrl),
            title: channel.name,
            userAgent: ua,
            headers: headers.isEmpty ? null : headers,
          )
        : variants.first;
    final fallbacks = variants.length <= 1
        ? const <MediaSource>[]
        : variants.sublist(1);

    final slot = MultiStreamSlot(
      channel: channel,
      source: primary,
      fallbacks: fallbacks,
    );
    final next = <MultiStreamSlot>[...state.slots, slot];
    final newIndex = next.length - 1;
    final activeIndex =
        state.slots.isEmpty ? 0 : state.safeActiveIndex;
    state = state.copyWith(
      slots: next,
      // The first added slot owns the audio; subsequent additions keep
      // the user's current focus instead of stealing it.
      activeSlotIndex: activeIndex,
    );
    return newIndex;
  }

  /// Removes the slot at [index]. No-op when out of range.
  ///
  /// When the removed slot was the active one, the active pointer
  /// shifts to the *previous* slot if any (preserving audio focus on
  /// the closest neighbour) or to 0 when removing the first slot.
  void removeSlot(int index) {
    if (index < 0 || index >= state.slots.length) return;
    final next = <MultiStreamSlot>[
      for (var i = 0; i < state.slots.length; i++)
        if (i != index) state.slots[i],
    ];
    var newActive = state.safeActiveIndex;
    if (next.isEmpty) {
      newActive = 0;
    } else if (index == state.activeSlotIndex) {
      newActive = (index - 1).clamp(0, next.length - 1);
    } else if (index < state.activeSlotIndex) {
      // Removing a slot before the active one shifts the active index
      // down by one to keep pointing at the same logical tile.
      newActive = state.activeSlotIndex - 1;
    }
    state = state.copyWith(
      slots: next,
      activeSlotIndex: newActive,
    );
  }

  /// Marks slot [index] as the audible tile. No-op on out-of-range or
  /// already-active.
  void setActive(int index) {
    if (index < 0 || index >= state.slots.length) return;
    if (index == state.activeSlotIndex) return;
    state = state.copyWith(activeSlotIndex: index);
  }

  /// Toggles the master mute. When on, every tile (including the
  /// active one) is silenced.
  void toggleMasterMute() {
    state = state.copyWith(masterMuted: !state.masterMuted);
  }

  /// Replaces the slot at [index] with a different channel. Useful when
  /// the user wants to swap one tile for another from the picker.
  void replaceSlot(int index, Channel channel) {
    if (index < 0 || index >= state.slots.length) return;
    final urls = streamUrlVariants(channel.streamUrl).map(proxify).toList();
    final ua = channel.extras['http-user-agent'] ??
        channel.extras['user-agent'];
    final referer = channel.extras['http-referrer'] ??
        channel.extras['referer'] ??
        channel.extras['Referer'];
    final headers = <String, String>{
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
    };
    final variants = MediaSource.variants(
      urls,
      title: channel.name,
      userAgent: ua,
      headers: headers.isEmpty ? null : headers,
    );
    final primary = variants.isEmpty
        ? MediaSource(
            url: proxify(channel.streamUrl),
            title: channel.name,
            userAgent: ua,
            headers: headers.isEmpty ? null : headers,
          )
        : variants.first;
    final fallbacks = variants.length <= 1
        ? const <MediaSource>[]
        : variants.sublist(1);
    final next = <MultiStreamSlot>[
      for (var i = 0; i < state.slots.length; i++)
        if (i == index)
          MultiStreamSlot(
            channel: channel,
            source: primary,
            fallbacks: fallbacks,
          )
        else
          state.slots[i],
    ];
    state = state.copyWith(slots: next);
  }

  /// Tears down the session. Slots vanish, active resets to 0.
  void clear() {
    state = const MultiStreamState();
  }
}
