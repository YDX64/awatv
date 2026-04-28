import 'dart:async';

import 'package:awatv_player/awatv_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of the sleep-timer state. Player widgets watch this via
/// [sleepTimerProvider].
class SleepTimerSnapshot {
  const SleepTimerSnapshot({
    this.isActive = false,
    this.duration,
    this.endsAt,
    this.fading = false,
  });

  /// `true` while a timer is counting down.
  final bool isActive;

  /// Total duration the user picked. `null` when the timer is off or the
  /// user picked the special "end of programme" option (in which case
  /// [endsAt] is still set).
  final Duration? duration;

  /// UTC timestamp at which the timer fires. `null` when inactive.
  final DateTime? endsAt;

  /// `true` while we're inside the 10-second audio fade. UI can show
  /// the fade in the chip ("Sönüyor…").
  final bool fading;

  /// Live remaining time. `null` when inactive.
  Duration? remaining(DateTime now) {
    if (!isActive) return null;
    final ends = endsAt;
    if (ends == null) return null;
    final delta = ends.difference(now);
    return delta.isNegative ? Duration.zero : delta;
  }
}

/// Sleep timer Riverpod state. We keep a manual [Timer] alive on the
/// notifier so the countdown survives navigation away from the
/// player — handy for "leave the player up while I read for 10
/// minutes" flows.
class SleepTimerNotifier extends StateNotifier<SleepTimerSnapshot> {
  SleepTimerNotifier() : super(const SleepTimerSnapshot());

  Timer? _timer;
  Timer? _fadeTimer;
  AwaPlayerController? _attached;
  double? _fadeStartVolume;

  /// Attach a player so the timer can fade audio + pause when it
  /// fires. The player screen calls this on mount and `null`s it on
  /// dispose.
  void attachController(AwaPlayerController? controller) {
    _attached = controller;
  }

  /// Set or replace the timer. Pass `null` to cancel.
  void set(Duration? duration) {
    cancel();
    if (duration == null || duration <= Duration.zero) return;
    final endsAt = DateTime.now().toUtc().add(duration);
    state = SleepTimerSnapshot(
      isActive: true,
      duration: duration,
      endsAt: endsAt,
    );
    _timer = Timer(duration, _fire);
  }

  /// Special "stop at programme end" preset — accepts a precomputed
  /// `endsAt` so callers (player_screen) can derive it from the EPG /
  /// VOD duration before scheduling.
  void setUntil(DateTime endsAt) {
    cancel();
    final delta = endsAt.toUtc().difference(DateTime.now().toUtc());
    if (delta <= Duration.zero) return;
    state = SleepTimerSnapshot(
      isActive: true,
      endsAt: endsAt.toUtc(),
    );
    _timer = Timer(delta, _fire);
  }

  void cancel() {
    _timer?.cancel();
    _fadeTimer?.cancel();
    _timer = null;
    _fadeTimer = null;
    if (_fadeStartVolume != null) {
      _attached?.setVolume(_fadeStartVolume! * 100);
      _fadeStartVolume = null;
    }
    state = const SleepTimerSnapshot();
  }

  Future<void> _fire() async {
    state = SleepTimerSnapshot(
      isActive: state.isActive,
      duration: state.duration,
      endsAt: state.endsAt,
      fading: true,
    );
    final c = _attached;
    if (c == null) {
      // No player attached — just emit the snapshot transition. The
      // outer widget can show the toast.
      _onFadeComplete();
      return;
    }
    // Read the current volume so we can restore it if the user wakes
    // back up and disables the timer mid-fade. The player API exposes
    // the live value through `volume` getter on the underlying engine,
    // but for safety we assume 1.0 when unknown — worst case we
    // restore to 1.0 after a cancel.
    _fadeStartVolume = 1;
    const totalSteps = 20;
    const stepDuration = Duration(milliseconds: 500);
    var step = 0;
    _fadeTimer = Timer.periodic(stepDuration, (Timer t) async {
      step += 1;
      final factor = 1 - (step / totalSteps);
      final clamped = factor.clamp(0.0, 1.0);
      try {
        await c.setVolume(clamped * 100);
      } on Object {
        // Swallow — the player may have been torn down mid-fade.
      }
      if (step >= totalSteps) {
        t.cancel();
        try {
          await c.pause();
        } on Object {
          // Best-effort.
        }
        _onFadeComplete();
      }
    });
  }

  void _onFadeComplete() {
    state = const SleepTimerSnapshot();
    _timer = null;
    _fadeTimer = null;
    _fadeStartVolume = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeTimer?.cancel();
    super.dispose();
  }
}

/// Single shared sleep-timer state. `keepAlive`-equivalent because the
/// `StateNotifierProvider` is global and lives for the app's lifetime.
final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerSnapshot>(
  (Ref ref) => SleepTimerNotifier(),
);

/// One-second tick that the chip rebuilds against. Rebuilds are scoped
/// to widgets that explicitly watch this provider, so the rest of the
/// player doesn't pay for the periodic rebuild.
final sleepTimerTickProvider = StreamProvider<DateTime>((Ref ref) async* {
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now(),
  );
});
