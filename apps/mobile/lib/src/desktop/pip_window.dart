import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:awatv_mobile/src/desktop/always_on_top.dart';
import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:window_manager/window_manager.dart';

part 'pip_window.g.dart';

/// Hive box that stores the geometry to restore after exiting PiP. Kept
/// distinct from `desktop_window_prefs` so a crash mid-PiP can't corrupt
/// the user's preferred non-PiP layout.
const String _pipPrefsBox = 'desktop_pip_prefs';
const String _kPrevW = 'prev_w';
const String _kPrevH = 'prev_h';
const String _kPrevX = 'prev_x';
const String _kPrevY = 'prev_y';
const String _kPrevMaximized = 'prev_max';
const String _kPrevFullscreen = 'prev_fs';
const String _kInPip = 'in_pip';

/// Compact PiP window dimensions — 16:9 at 400px wide. Fits comfortably
/// in a screen corner without overlapping most desktop dock layouts.
const Size _pipSize = Size(400, 225);

/// Distance from the screen edge to the PiP window in logical pixels.
const double _pipMargin = 20;

/// Riverpod state holder for "is the app currently in PiP compact mode?".
///
/// The player screen watches this to swap in a minimal layout (no nav,
/// no top bar — just the video frame and a tiny exit-PiP affordance).
/// Kept-alive so it survives route changes; the user toggling between
/// home and player while PiP is active retains the compact flag.
@Riverpod(keepAlive: true)
class PipMode extends _$PipMode {
  @override
  bool build() => false;

  // ignore: use_setters_to_change_properties
  void set(bool active) => state = active;
}

/// Convenience controller that owns the actual window-manager calls and
/// keeps the Riverpod state in sync. Designed to be a single shared
/// instance — wire it via [pipWindowControllerProvider].
class PipWindowController {
  PipWindowController(this._ref);

  final Ref _ref;
  bool _busy = false;

  /// True when the OS window is currently in compact PiP form.
  bool get isActive => _ref.read(pipModeProvider);

  /// Toggles PiP. No-op on non-desktop platforms.
  Future<void> toggle() async {
    if (isActive) {
      await exit();
    } else {
      await enter();
    }
  }

  /// Saves the current geometry and shrinks the window into a small
  /// always-on-top frame in the bottom-right corner.
  Future<void> enter() async {
    if (!isDesktopRuntime() || _busy) return;
    _busy = true;
    try {
      // Capture the pre-PiP geometry so we can restore it on exit.
      final wasFullscreen = await _safe(windowManager.isFullScreen) ?? false;
      if (wasFullscreen) {
        await _safe(() => windowManager.setFullScreen(false));
      }
      final wasMaximized = await _safe(windowManager.isMaximized) ?? false;
      Rect? bounds;
      if (!wasMaximized) {
        bounds = await _safe(windowManager.getBounds);
      }

      await _persistPrePipGeometry(
        bounds: bounds,
        maximized: wasMaximized,
        fullscreen: wasFullscreen,
      );

      // Compute corner anchor. We bias toward bottom-right using the
      // first attached display the OS reports for the window. If we
      // can't read screen bounds for any reason, the window simply
      // appears centered — still usable.
      Offset target = Offset.zero;
      try {
        final screen = PlatformDispatcher.instance.views.first;
        final size = screen.physicalSize / screen.devicePixelRatio;
        target = Offset(
          (size.width - _pipSize.width - _pipMargin).clamp(
            0.0,
            size.width,
          ),
          (size.height - _pipSize.height - _pipMargin).clamp(
            0.0,
            size.height,
          ),
        );
      } on Object {
        // Leave at origin — caller can drag.
      }

      // Apply compact geometry. Order matters on Windows: clear the
      // maximized/full-screen state first, then resize, then anchor.
      if (wasMaximized) {
        await _safe(windowManager.unmaximize);
      }
      await _safe(() => windowManager.setMinimumSize(const Size(320, 180)));
      await _safe(
        () => windowManager.setBounds(
          Rect.fromLTWH(
            target.dx,
            target.dy,
            _pipSize.width,
            _pipSize.height,
          ),
          animate: true,
        ),
      );
      // PiP always pins the compact window — the whole point of PiP is
      // a floating frame the user can keep on top of other windows.
      // We bypass the user's `alwaysOnTopProvider` preference here so a
      // user who has it off still gets a usable PiP; on `exit()` below
      // we ask the provider to re-apply the *saved* preference so the
      // toggle the user actually set is what survives.
      await _safe(() => windowManager.setAlwaysOnTop(true));
      // Hides the taskbar entry on Windows so the floating window
      // doesn't take a slot in the taskbar group; macOS keeps the dock
      // tile (hiding it requires LSUIElement which would prevent menu
      // bar use entirely).
      if (Platform.isWindows) {
        await _safe(() => windowManager.setSkipTaskbar(true));
      }
      // Hide titlebar buttons so the bare frame reads as a media tile.
      await _safe(() => windowManager.setHasShadow(true));
      _ref.read(pipModeProvider.notifier).set(true);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[pip] enter failed: $e');
      _ref.read(pipModeProvider.notifier).set(false);
    } finally {
      _busy = false;
    }
  }

  /// Restores the pre-PiP geometry and clears the always-on-top flag.
  Future<void> exit() async {
    if (!isDesktopRuntime() || _busy) return;
    _busy = true;
    try {
      final saved = await _readPrePipGeometry();
      // Defer the always-on-top reset to the provider so the user's
      // saved preference survives a PiP round-trip. If the user had
      // pinned the window before entering PiP, we want it pinned after.
      // The provider's `reapply` is a no-op when the saved preference
      // is `false`, mirroring the previous behaviour for users who
      // never enabled the feature.
      try {
        await _ref.read(alwaysOnTopProvider.notifier).reapply();
      } on Object {
        // Provider hasn't been initialised (rare — it's keep-alive and
        // boot-loaded). Fall back to clearing the flag explicitly so
        // the OS state at least matches the new (post-PiP) UI.
        await _safe(() => windowManager.setAlwaysOnTop(false));
      }
      if (Platform.isWindows) {
        await _safe(() => windowManager.setSkipTaskbar(false));
      }
      // Restore the user's preferred minimum size before resizing back.
      await _safe(() => windowManager.setMinimumSize(const Size(800, 600)));

      if (saved.bounds != null) {
        await _safe(
          () => windowManager.setBounds(saved.bounds!, animate: true),
        );
      }
      if (saved.maximized) {
        await _safe(windowManager.maximize);
      }
      if (saved.fullscreen) {
        await _safe(() => windowManager.setFullScreen(true));
      }
      await _clearPrePipFlag();
      _ref.read(pipModeProvider.notifier).set(false);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[pip] exit failed: $e');
      // Always clear the flag so the UI doesn't get stuck in compact mode.
      _ref.read(pipModeProvider.notifier).set(false);
    } finally {
      _busy = false;
    }
  }

  /// Restore PiP geometry on app boot if the previous run exited while
  /// in PiP. Called from the boot path; safe to invoke unconditionally.
  static Future<bool> wasInPipOnLastRun() async {
    try {
      final box = await Hive.openBox<dynamic>(_pipPrefsBox);
      return box.get(_kInPip) as bool? ?? false;
    } on Object {
      return false;
    }
  }
}

class _PrePipGeometry {
  const _PrePipGeometry({
    this.bounds,
    this.maximized = false,
    this.fullscreen = false,
  });
  final Rect? bounds;
  final bool maximized;
  final bool fullscreen;
}

Future<void> _persistPrePipGeometry({
  required Rect? bounds,
  required bool maximized,
  required bool fullscreen,
}) async {
  try {
    final box = await Hive.openBox<dynamic>(_pipPrefsBox);
    final entries = <String, dynamic>{
      _kPrevMaximized: maximized,
      _kPrevFullscreen: fullscreen,
      _kInPip: true,
    };
    if (bounds != null) {
      entries[_kPrevW] = bounds.width;
      entries[_kPrevH] = bounds.height;
      entries[_kPrevX] = bounds.left;
      entries[_kPrevY] = bounds.top;
    }
    await box.putAll(entries);
  } on Object catch (e) {
    if (kDebugMode) debugPrint('[pip] persist failed: $e');
  }
}

Future<_PrePipGeometry> _readPrePipGeometry() async {
  try {
    final box = await Hive.openBox<dynamic>(_pipPrefsBox);
    final w = (box.get(_kPrevW) as num?)?.toDouble();
    final h = (box.get(_kPrevH) as num?)?.toDouble();
    final x = (box.get(_kPrevX) as num?)?.toDouble();
    final y = (box.get(_kPrevY) as num?)?.toDouble();
    final maximized = box.get(_kPrevMaximized) as bool? ?? false;
    final fullscreen = box.get(_kPrevFullscreen) as bool? ?? false;
    Rect? bounds;
    if (w != null && h != null && x != null && y != null) {
      bounds = Rect.fromLTWH(x, y, w, h);
    }
    return _PrePipGeometry(
      bounds: bounds,
      maximized: maximized,
      fullscreen: fullscreen,
    );
  } on Object {
    return const _PrePipGeometry();
  }
}

Future<void> _clearPrePipFlag() async {
  try {
    final box = await Hive.openBox<dynamic>(_pipPrefsBox);
    await box.put(_kInPip, false);
  } on Object {
    // best-effort
  }
}

/// Shared controller. Lazily created — the boot path wires it up via
/// [pipWindowControllerProvider] before any UI consumer asks for it.
@Riverpod(keepAlive: true)
PipWindowController pipWindowController(Ref ref) {
  return PipWindowController(ref);
}

/// Wraps a possibly-throwing window_manager call so a single failed
/// platform invocation doesn't take down the entire PiP transition.
Future<T?> _safe<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on Object catch (e) {
    if (kDebugMode) debugPrint('[pip] window call failed: $e');
    return null;
  }
}
