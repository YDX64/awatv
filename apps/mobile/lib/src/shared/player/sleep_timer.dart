import 'dart:async';

import 'package:awatv_player/awatv_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What triggered the active sleep timer. Surfaced in the chip / sheet
/// so the user can tell at a glance whether the player will stop after
/// "30 dakika" or "Bolum sonunda".
enum SleepTriggerKind {
  /// User-picked fixed duration (15/30/45/60/90/custom minutes).
  duration,

  /// Fire when the current EPG programme ends (live channels).
  endOfProgramme,

  /// Fire when the current VOD/episode duration runs out.
  endOfEpisode,

  /// User picked an absolute time-of-day.
  custom,
}

/// Snapshot of the sleep-timer state. Player widgets watch this via
/// [sleepTimerProvider].
class SleepTimerSnapshot {
  const SleepTimerSnapshot({
    this.isActive = false,
    this.duration,
    this.endsAt,
    this.fading = false,
    this.trigger,
  });

  /// `true` while a timer is counting down.
  final bool isActive;

  /// Total duration the user picked. `null` when the timer is off or the
  /// user picked one of the EPG / episode triggers (in which case
  /// [endsAt] is still set).
  final Duration? duration;

  /// UTC timestamp at which the timer fires. `null` when inactive.
  final DateTime? endsAt;

  /// `true` while we're inside the 10-second audio fade. UI can show
  /// the fade in the chip ("Sönüyor…").
  final bool fading;

  /// What kind of trigger produced this snapshot. Helps the chip render
  /// the right secondary line ("Bolum sonu" vs "30 dakika kaldi").
  final SleepTriggerKind? trigger;

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

  /// Set or replace the timer with a fixed [duration]. Pass `null`
  /// (or `Duration.zero`) to cancel.
  void set(
    Duration? duration, {
    SleepTriggerKind trigger = SleepTriggerKind.duration,
  }) {
    cancel();
    if (duration == null || duration <= Duration.zero) return;
    final endsAt = DateTime.now().toUtc().add(duration);
    state = SleepTimerSnapshot(
      isActive: true,
      duration: duration,
      endsAt: endsAt,
      trigger: trigger,
    );
    _timer = Timer(duration, _fire);
  }

  /// Special "stop at programme end" / "end of episode" / "custom time"
  /// preset — accepts a precomputed `endsAt` so callers can derive it
  /// from the EPG / VOD duration / user-picked clock-time before
  /// scheduling. [trigger] tags the snapshot so UI can label it
  /// correctly.
  void setUntil(
    DateTime endsAt, {
    SleepTriggerKind trigger = SleepTriggerKind.endOfProgramme,
  }) {
    cancel();
    final delta = endsAt.toUtc().difference(DateTime.now().toUtc());
    if (delta <= Duration.zero) return;
    state = SleepTimerSnapshot(
      isActive: true,
      endsAt: endsAt.toUtc(),
      trigger: trigger,
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
      trigger: state.trigger,
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

// ---------------------------------------------------------------------------
// "Are you still watching?" continuous-playback gate
// ---------------------------------------------------------------------------

/// Snapshot of the continuous-watching tracker.
///
/// The player publishes start/stop ticks here; once we accumulate
/// [StillWatchingNotifier.threshold] of *consecutive* playback, the
/// notifier flips [shouldPrompt] true. The player widget watches this
/// flag and pauses + shows the overlay when it goes high.
class StillWatchingState {
  const StillWatchingState({
    this.shouldPrompt = false,
    this.startedAt,
    this.lastTickAt,
  });

  /// True when the threshold has been crossed. Cleared by
  /// [StillWatchingNotifier.acknowledged].
  final bool shouldPrompt;

  /// UTC time the current contiguous run began.
  final DateTime? startedAt;

  /// Last time the player published a tick — used to detect pauses
  /// longer than [StillWatchingNotifier.idleResetWindow] and reset.
  final DateTime? lastTickAt;
}

/// Tracks "is the user still watching?" state.
///
/// The player calls [tick] roughly once per second while playback is
/// going; [paused] when the user manually pauses. After
/// [threshold] of contiguous play (default 4h), the notifier flips
/// [StillWatchingState.shouldPrompt] high and the player overlay takes
/// over. [acknowledged] clears the flag and resets the run, so the
/// next 4h of uninterrupted playback fires the overlay again.
class StillWatchingNotifier extends StateNotifier<StillWatchingState> {
  StillWatchingNotifier({
    Duration threshold = const Duration(hours: 4),
    Duration idleResetWindow = const Duration(minutes: 5),
  })  : threshold = threshold,
        idleResetWindow = idleResetWindow,
        super(const StillWatchingState());

  final Duration threshold;
  final Duration idleResetWindow;

  /// Called from the player while playback is alive. If the gap since
  /// [StillWatchingState.lastTickAt] is bigger than [idleResetWindow]
  /// the run resets — the user clearly wandered off and came back.
  void tick() {
    final now = DateTime.now().toUtc();
    final last = state.lastTickAt;
    final started = state.startedAt;
    if (started == null || last == null) {
      state = StillWatchingState(
        startedAt: now,
        lastTickAt: now,
        shouldPrompt: state.shouldPrompt,
      );
      return;
    }
    if (now.difference(last) > idleResetWindow) {
      state = StillWatchingState(
        startedAt: now,
        lastTickAt: now,
      );
      return;
    }
    final cumulative = now.difference(started);
    final shouldPrompt = state.shouldPrompt || cumulative >= threshold;
    state = StillWatchingState(
      startedAt: started,
      lastTickAt: now,
      shouldPrompt: shouldPrompt,
    );
  }

  /// Player paused — pause the count too. We keep `startedAt` so a
  /// short pause (under `idleResetWindow`) still counts toward the
  /// threshold.
  void paused() {
    state = StillWatchingState(
      shouldPrompt: state.shouldPrompt,
      startedAt: state.startedAt,
      lastTickAt: state.lastTickAt,
    );
  }

  /// User answered the prompt with "Evet" — clear the flag and reset
  /// the run so the next 4h of contiguous playback gates again.
  void acknowledged() {
    final now = DateTime.now().toUtc();
    state = StillWatchingState(
      startedAt: now,
      lastTickAt: now,
    );
  }

  /// Player closed entirely — drop everything.
  void reset() {
    state = const StillWatchingState();
  }
}

/// Shared notifier — single instance per app. `StateNotifierProvider`
/// lifecycle persists for the app's lifetime so the run survives
/// navigation between the player and other screens.
final stillWatchingProvider =
    StateNotifierProvider<StillWatchingNotifier, StillWatchingState>(
  (Ref ref) => StillWatchingNotifier(),
);
