import 'package:awatv_player/awatv_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controller-of-controllers — exposes the live [AwaPlayerController]
/// that is currently driving on-screen playback.
///
/// The persistent player bar reads this provider to wire its play/pause,
/// volume, and channel-prev/next buttons directly to the engine without
/// taking a build-time dependency on the player screen. The companion
/// `nowPlayingProvider` mirrors *display* state (title, position, isLive,
/// thumbnail); this provider is for *control*.
///
/// Lifecycle:
///   - PlayerScreen / TvPlayerScreen call [attach] right after a fresh
///     controller is constructed, and call [detach] in their `dispose()`.
///   - The bar reads the value via `ref.watch(activePlayerControllerProvider)`.
///     A null value (e.g. during route transitions when the previous
///     controller has detached but the new one has not yet attached) is
///     interpreted by the bar as "controls disabled".
class ActivePlayerControllerNotifier extends Notifier<AwaPlayerController?> {
  @override
  AwaPlayerController? build() => null;

  /// Records [c] as the active controller. Called by the player screen
  /// after `_bootController()` constructs an `AwaPlayerController.empty`.
  // ignore: use_setters_to_change_properties
  void attach(AwaPlayerController c) {
    state = c;
  }

  /// Drops the active controller pointer if (and only if) [c] is still
  /// the registered controller. Guarding on identity prevents a stale
  /// player screen's `dispose()` from clearing a pointer the new screen
  /// has already taken over (during fast route transitions).
  void detach(AwaPlayerController c) {
    if (identical(state, c)) {
      state = null;
    }
  }

  /// Force-clear regardless of identity. Used in test/cleanup paths only.
  void clear() {
    state = null;
  }
}

/// Active controller pointer. Kept-alive for the app lifetime — the
/// persistent player bar lives outside the player route and would lose
/// its handle to the engine if this provider auto-disposed.
final activePlayerControllerProvider =
    NotifierProvider<ActivePlayerControllerNotifier, AwaPlayerController?>(
  ActivePlayerControllerNotifier.new,
);
