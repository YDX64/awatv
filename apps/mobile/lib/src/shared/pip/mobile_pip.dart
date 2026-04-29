import 'dart:async';
import 'dart:io' show Platform;

import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_pip.g.dart';

/// Whether PiP is currently active for the host activity / scene.
///
/// On Android the floating package emits a status stream we mirror into
/// this provider. On iOS we toggle it manually around our method-channel
/// call because `AVPictureInPictureController` doesn't surface a Dart-side
/// state stream — the AppDelegate-side delegate could push events back,
/// but for now the player only needs to know *whether* it asked for PiP
/// so it can render a slimmer control layer.
///
/// Kept-alive because the player screen mounts and unmounts frequently
/// while PiP is active (PiP outlives the route on iOS in particular —
/// the OS shrinks the whole scene).
@Riverpod(keepAlive: true)
class MobilePipMode extends _$MobilePipMode {
  @override
  bool build() => false;

  // ignore: use_setters_to_change_properties
  void set(bool active) => state = active;
}

/// Result of a PiP request.
enum MobilePipResult {
  /// PiP entered successfully (Android: foreground activity shrank;
  /// iOS: AVPictureInPictureController started).
  entered,

  /// The platform reported PiP is unsupported on this device. Common
  /// on Android < 8.0 (API 26), iPad models with the old multitasking
  /// model disabled, and iPhone SE 1st gen.
  unsupported,

  /// PiP is supported but the user has disabled it in OS settings —
  /// Android Picture-in-picture per-app toggle, iOS "Start PiP
  /// Automatically" + the per-app permission switch.
  disabled,

  /// The platform call threw. The error is surfaced via
  /// [MobilePipException] so the host UI can show a snack.
  failed,

  /// We're not on a platform that supports native PiP at all (web,
  /// desktop, TV). The host UI usually short-circuits before reaching
  /// here, but [MobilePip] returns this verdict so callers don't have
  /// to repeat the platform check.
  notMobile,
}

/// Surfaced when the platform call fails for a reason that isn't
/// covered by the [MobilePipResult] enum (typically a method-channel
/// transport error).
class MobilePipException implements Exception {
  MobilePipException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'MobilePipException: $message'
      '${cause == null ? '' : ' (cause: $cause)'}';
}

/// Cross-platform Picture-in-Picture facade.
///
/// On Android: wraps the `floating` package's
/// `Floating().enable(ImmediatePiP(aspectRatio: ...))` call which
/// triggers `Activity.enterPictureInPictureMode(...)` underneath.
///
/// On iOS: uses a method channel `awatv/mobile_pip` that the host
/// `AppDelegate` extension implements against the active player's
/// AVPlayerLayer. media_kit on iOS exposes the underlying AVPlayer for
/// each controller — but the public API is currently limited, so the
/// channel falls back to "best-effort": tell the OS we want PiP and let
/// it pick up whichever AVPlayerLayer is currently in the foreground.
///
/// All methods are safe to call from any platform — they short-circuit
/// to [MobilePipResult.notMobile] on web / desktop / TV. Every platform
/// call is guarded with try/catch so a missing plugin never crashes the
/// host app.
class MobilePip {
  MobilePip._();

  /// Method channel for the iOS-side AVPictureInPictureController bridge.
  /// The Android side uses the `floating` package's own channel.
  static const MethodChannel _iosChannel =
      MethodChannel('awatv/mobile_pip');

  /// Cached `Floating()` instance. Cheap to instantiate, but the package
  /// expects the same instance across enter/exit/listen calls so we keep
  /// one in the static scope. Lazily created so platforms that never
  /// touch PiP don't pay the construction cost.
  static Floating? _floating;
  static StreamSubscription<PiPStatus>? _statusSub;

  /// Returns true when the host platform can satisfy native PiP.
  ///
  /// Android 8.0+ (API 26) is required for the
  /// `enterPictureInPictureMode` API; older devices return
  /// [MobilePipResult.unsupported] from [enter]. iOS has supported AVPiP
  /// since iOS 14 / iPadOS 14 — the bridge falls back gracefully on
  /// older devices.
  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Probes the platform for whether PiP is currently *available* —
  /// stricter than [isPlatformSupported] because the user may have
  /// turned it off in OS settings or be on a fork of Android that
  /// stripped the API.
  static Future<bool> isAvailable() async {
    if (!isPlatformSupported) return false;
    try {
      if (Platform.isAndroid) {
        final f = _ensureFloating();
        final status = await f.isPipAvailable;
        return status;
      }
      if (Platform.isIOS) {
        final supported =
            await _iosChannel.invokeMethod<bool>('isSupported');
        return supported ?? false;
      }
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[mobile_pip] isAvailable failed: $e');
    }
    return false;
  }

  /// Enters PiP mode.
  ///
  /// On Android we request an [ImmediatePiP] frame at `aspectRatio` —
  /// `floating` clamps to the OS-allowed aspect-ratio range (1:2.39 ..
  /// 2.39:1) so we don't have to.
  ///
  /// On iOS we tell the bridge to call
  /// `AVPictureInPictureController.start()` against the foreground
  /// AVPlayerLayer. The bridge no-ops if PiP is already running.
  ///
  /// Returns the resolved [MobilePipResult] so callers can pick the
  /// right user-facing message ("PiP yok" vs "PiP kapali — Ayarlar'dan
  /// ac" vs a generic error toast).
  static Future<MobilePipResult> enter({
    Rational aspectRatio = const Rational.landscape(),
  }) async {
    if (!isPlatformSupported) return MobilePipResult.notMobile;
    try {
      if (Platform.isAndroid) {
        final f = _ensureFloating();
        final available = await f.isPipAvailable;
        if (!available) return MobilePipResult.unsupported;
        final status = await f.enable(
          ImmediatePiP(aspectRatio: aspectRatio),
        );
        // floating returns the *new* PipStatus; treat anything other
        // than enabled as a failure so the caller can fall back to a
        // snack rather than silently appearing to succeed.
        switch (status) {
          case PiPStatus.enabled:
          case PiPStatus.automatic:
            return MobilePipResult.entered;
          case PiPStatus.disabled:
            return MobilePipResult.disabled;
          case PiPStatus.unavailable:
            return MobilePipResult.unsupported;
        }
      }
      if (Platform.isIOS) {
        final ok = await _iosChannel.invokeMethod<bool>(
          'enter',
          <String, dynamic>{
            'aspectNumerator': aspectRatio.numerator,
            'aspectDenominator': aspectRatio.denominator,
          },
        );
        return (ok ?? false)
            ? MobilePipResult.entered
            : MobilePipResult.unsupported;
      }
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[mobile_pip] enter platform err: $e');
      // Map common iOS error codes to the granular result enum so the
      // host can show "PiP kapali" vs "PiP destegi yok".
      final code = e.code.toLowerCase();
      if (code.contains('disabled') || code.contains('denied')) {
        return MobilePipResult.disabled;
      }
      if (code.contains('unsupported') || code.contains('unavailable')) {
        return MobilePipResult.unsupported;
      }
      return MobilePipResult.failed;
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[mobile_pip] enter unexpected: $e');
      return MobilePipResult.failed;
    }
    return MobilePipResult.notMobile;
  }

  /// Restores the regular full-screen window.
  ///
  /// On Android the `floating` package owns the lifecycle — we call its
  /// `cancelOnLeavePiP()` and trust the OS to expand the activity. On
  /// iOS the bridge invokes `AVPictureInPictureController.stop()`.
  static Future<MobilePipResult> exit() async {
    if (!isPlatformSupported) return MobilePipResult.notMobile;
    try {
      if (Platform.isAndroid) {
        // floating doesn't expose an explicit "exit" — the OS owns it.
        // Cancelling the auto-leave watcher is the closest analogue and
        // stops the package from re-entering on backgrounding. The
        // user can also tap the PiP frame's expand button.
        final f = _ensureFloating();
        f.cancelOnLeavePiP();
        return MobilePipResult.entered; // best-effort; OS owns the rest
      }
      if (Platform.isIOS) {
        final ok = await _iosChannel.invokeMethod<bool>('exit');
        return (ok ?? false)
            ? MobilePipResult.entered
            : MobilePipResult.failed;
      }
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[mobile_pip] exit failed: $e');
      return MobilePipResult.failed;
    }
    return MobilePipResult.notMobile;
  }

  /// Asks the platform to enter PiP automatically the next time the
  /// activity / scene goes to the background.
  ///
  /// Premium users with auto-PiP enabled get this called from the
  /// player screen's `didChangeAppLifecycleState` hook — when the OS
  /// reports the app is about to be backgrounded we ask for PiP first
  /// so the user lands on a floating window instead of a frozen home
  /// screen.
  ///
  /// On iOS the API is `setRequiresLinearPlayback` + the system handles
  /// the rest if the AVPlayerLayer is on screen; we proxy through the
  /// channel so the AppDelegate side can keep a single source of truth.
  static Future<void> setAutoEnter({
    required bool enabled,
    Rational aspectRatio = const Rational.landscape(),
  }) async {
    if (!isPlatformSupported) return;
    try {
      if (Platform.isAndroid) {
        final f = _ensureFloating();
        if (enabled) {
          await f.enable(OnLeavePiP(aspectRatio: aspectRatio));
        } else {
          f.cancelOnLeavePiP();
        }
      }
      if (Platform.isIOS) {
        await _iosChannel.invokeMethod<void>(
          'setAutoEnter',
          <String, dynamic>{
            'enabled': enabled,
            'aspectNumerator': aspectRatio.numerator,
            'aspectDenominator': aspectRatio.denominator,
          },
        );
      }
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[mobile_pip] setAutoEnter failed: $e');
    }
  }

  /// Subscribes to platform-side PiP state transitions and pumps them
  /// into [mobilePipModeProvider].
  ///
  /// Idempotent — calling twice does not stack subscriptions. On
  /// platforms that don't expose a status stream (iOS today; the
  /// channel can push if AppDelegate posts events) this is a no-op
  /// and the host code keeps the provider in sync manually around its
  /// `enter()` / `exit()` calls.
  // ignore: avoid_positional_boolean_parameters
  static Future<void> wireStatusStream(
    void Function(bool active) onChange,
  ) async {
    await _statusSub?.cancel();
    _statusSub = null;
    if (!isPlatformSupported) return;
    if (Platform.isAndroid) {
      try {
        final f = _ensureFloating();
        _statusSub = f.pipStatusStream.listen(
          (PiPStatus s) {
            final active = s == PiPStatus.enabled ||
                s == PiPStatus.automatic;
            onChange(active);
          },
          onError: (Object e, StackTrace _) {
            if (kDebugMode) debugPrint('[mobile_pip] stream err: $e');
          },
        );
      } on Object catch (e) {
        if (kDebugMode) debugPrint('[mobile_pip] wire stream failed: $e');
      }
      return;
    }
    if (Platform.isIOS) {
      // iOS surfaces transitions through method channel callbacks.
      _iosChannel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'pipStateChanged') {
          final args = call.arguments;
          final active = args is Map && args['active'] == true;
          onChange(active);
        }
      });
    }
  }

  /// Builds an Android-friendly PiP-aware widget tree.
  ///
  /// On Android the `floating` package needs the player widget wrapped
  /// in a `PiPSwitcher` so it can swap to a compact layout the moment
  /// the OS shrinks the activity. On every other platform we return
  /// [child] unchanged — iOS handles the surface natively through the
  /// AVPlayerLayer, web/desktop/TV don't have native PiP at all.
  static Widget wrap({
    required Widget child,
    Widget? compactChild,
  }) {
    if (kIsWeb || !Platform.isAndroid) return child;
    return PiPSwitcher(
      childWhenEnabled: compactChild ?? child,
      childWhenDisabled: child,
    );
  }

  static Floating _ensureFloating() {
    return _floating ??= Floating();
  }
}
