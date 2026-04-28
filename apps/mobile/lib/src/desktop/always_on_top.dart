import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:window_manager/window_manager.dart';

part 'always_on_top.g.dart';

/// Hive box that stores the user's "pin window on top" preference.
///
/// Kept distinct from the other desktop prefs boxes (`desktop_window_prefs`,
/// `desktop_pip_prefs`) so a corrupt geometry write can't take the
/// preference down with it — and vice versa.
const String _alwaysOnTopBox = 'desktop_always_on_top_prefs';
const String _kEnabled = 'enabled';

/// Premium-gated "pin player window above all others" controller.
///
/// Three concerns live here:
///
///   1. **Persistence.** The user's choice survives across app restarts via
///      the dedicated [_alwaysOnTopBox] Hive box.
///   2. **Native sync.** Every state change is mirrored onto the OS window
///      via `window_manager.setAlwaysOnTop`. The call is wrapped in
///      try/catch — `window_manager` has been seen to throw on certain
///      Linux compositors when the window isn't fully attached yet, and
///      we never want a cosmetic preference to crash the app.
///   3. **PiP coexistence.** `pip_window.dart` forces the always-on-top
///      flag while in compact PiP mode regardless of the persisted
///      preference, then calls back into [setEnabled] on exit so the
///      user's actual choice is restored. Persistence and native sync
///      are decoupled (see [setEnabled] vs [_applyNative]) so PiP can
///      apply native changes without overwriting the user's saved value.
///
/// Web / mobile / TV runtimes bypass the native call entirely; the
/// notifier still keeps a `false` state so any consumer that reads it
/// (e.g. a tray menu rebuild on mixed runtimes) gets a stable answer.
@Riverpod(keepAlive: true)
class AlwaysOnTop extends _$AlwaysOnTop {
  @override
  bool build() {
    // Schedule a post-frame restore so we don't block the first frame on
    // disk I/O or a window-manager method-channel call. The notifier
    // starts at `false` and updates to the persisted value once the box
    // opens — virtually instant on any modern desktop.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _restoreFromDisk();
    });
    return false;
  }

  /// Toggles the preference. Returns the new state.
  Future<bool> toggle() async {
    final next = !state;
    await _set(next, persist: true);
    return next;
  }

  /// Public setter. Persists the new value and pushes it to the OS.
  Future<void> setEnabled(bool value) => _set(value, persist: true);

  /// Re-applies the *current* persisted preference to the OS window.
  ///
  /// Used by PiP exit: PiP forced always-on-top on regardless of the
  /// preference, so on exit we need to push the saved value back onto
  /// the window without altering the persisted state. Safe to call from
  /// any platform — no-ops off-desktop.
  Future<void> reapply() async {
    await _applyNative(state);
  }

  Future<void> _restoreFromDisk() async {
    try {
      final box = await Hive.openBox<dynamic>(_alwaysOnTopBox);
      final stored = box.get(_kEnabled) as bool? ?? false;
      // Avoid an unnecessary native call when the stored value matches
      // the default — boot is the hot path and `setAlwaysOnTop(false)`
      // costs a method-channel round-trip even when it's already off.
      if (!stored) return;
      await _set(true, persist: false);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[always_on_top] restore failed: $e');
      }
    }
  }

  Future<void> _set(bool value, {required bool persist}) async {
    if (state != value) {
      state = value;
    }
    await _applyNative(value);
    if (persist) {
      await _persist(value);
    }
  }

  Future<void> _applyNative(bool value) async {
    if (kIsWeb || !isDesktopRuntime()) return;
    try {
      await windowManager.setAlwaysOnTop(value);
    } on Object catch (e) {
      // window_manager throws on a few Linux compositors and during the
      // window's pre-attach window. Either way the preference is still
      // saved and the next reapply (e.g. on PiP exit) will retry.
      if (kDebugMode) {
        debugPrint('[always_on_top] setAlwaysOnTop($value) failed: $e');
      }
    }
  }

  Future<void> _persist(bool value) async {
    try {
      final box = await Hive.openBox<dynamic>(_alwaysOnTopBox);
      await box.put(_kEnabled, value);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[always_on_top] persist failed: $e');
      }
    }
  }
}
