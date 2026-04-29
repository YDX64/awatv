import 'dart:async';
import 'dart:io' show Platform;

import 'package:awatv_mobile/src/desktop/always_on_top.dart';
import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/desktop/pip_window.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/remote/player_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Stable menu-item keys. We rebuild the entire menu (tray_manager only
/// supports full-menu replacement) but route clicks via these keys so
/// the `onTrayMenuItemClick` switch can stay readable.
const String _kShow = 'show';
const String _kPip = 'pip';
const String _kAlwaysOnTop = 'always-on-top';
const String _kQuit = 'quit';
const String _kNowPlaying = 'nowplaying';

/// Default subtitle when no stream is loaded.
const String _kIdleLabel = 'Yayin yok';

/// Truncates the now-playing label so the tray menu doesn't blow out on
/// extra-long titles. macOS will silently grow to fit, but the result
/// looks cluttered next to the rest of the menu.
String _shorten(String text, {int max = 48}) {
  if (text.length <= max) return text;
  return '${text.substring(0, max - 1).trimRight()}…';
}

/// Owner of the macOS / Windows tray icon for AWAtv.
///
/// We deliberately keep this class procedural rather than a `Notifier` —
/// the tray_manager API is global state on the OS side, so contention
/// from multiple owners would race anyway. The single static `instance`
/// is initialised from `main.dart` after the window manager comes up.
class AwaTvTray with TrayListener {
  AwaTvTray._(this._ref);

  static AwaTvTray? _instance;

  final Ref _ref;
  String _nowPlaying = _kIdleLabel;
  bool _attached = false;

  /// One-shot init. Idempotent: calling twice is a no-op. Returns `true`
  /// when the tray icon and listener are now live.
  static Future<bool> initialise(Ref ref) async {
    if (!isDesktopRuntime()) return false;
    // tray_manager's Linux implementation is fragile — gate explicitly so
    // a missing libappindicator never crashes the boot.
    if (Platform.isLinux) return false;
    if (_instance != null) return _instance!._attached;

    final tray = AwaTvTray._(ref);
    final ok = await tray._attach();
    if (ok) _instance = tray;
    return ok;
  }

  /// Updates the now-playing label and rebuilds the menu. Safe to call
  /// from anywhere; rate-limited only by how often callers fire it.
  static Future<void> setNowPlaying(String? title) async {
    final inst = _instance;
    if (inst == null) return;
    inst._nowPlaying = (title == null || title.trim().isEmpty)
        ? _kIdleLabel
        : 'Şu an: ${_shorten(title.trim())}';
    await inst._publishMenu();
  }

  /// Tears down the listener — used by tests and graceful shutdown.
  static Future<void> dispose() async {
    final inst = _instance;
    if (inst == null) return;
    try {
      trayManager.removeListener(inst);
    } on Object {
      // best-effort
    }
    _instance = null;
  }

  Future<bool> _attach() async {
    try {
      // Setting the icon establishes the NSStatusItem on macOS / the
      // Win32 NOTIFYICONDATA on Windows. Must run after the engine has
      // attached — `runApp` handles that for us by the time tray_manager
      // executes its first method-channel call.
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/tray/tray.ico'
            : 'assets/tray/tray.png',
      );
      await trayManager.setToolTip('AWAtv');
      await _publishMenu();
      trayManager.addListener(this);
      _attached = true;

      // Listen for now-playing updates on the active playback context
      // so the tray label stays in sync without callers having to
      // remember to invoke setNowPlaying.
      _ref.listen<PlaybackContext?>(activePlaybackProvider, (
        PlaybackContext? _,
        PlaybackContext? next,
      ) {
        unawaited(setNowPlaying(next?.title));
      }, fireImmediately: true);

      // Always-on-top is a checkable menu entry; tray_manager doesn't
      // expose per-item updates, so we rebuild the whole menu when the
      // provider flips. Listening here (not inside `_publishMenu`) keeps
      // the listener attached for the lifetime of the tray. The
      // previous-value type is nullable on first emission.
      _ref.listen<bool>(alwaysOnTopProvider, (bool? _, bool __) {
        unawaited(_publishMenu());
      });

      // Same story for PiP — the menu copy on the PiP row depends on
      // whether we're currently compact, and the user can flip that from
      // the player overlay or a keyboard shortcut. Without this listener
      // the tray label drifts out of sync.
      _ref.listen<bool>(pipModeProvider, (bool? _, bool __) {
        unawaited(_publishMenu());
      });

      return true;
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[tray] init failed: $e');
      return false;
    }
  }

  Future<void> _publishMenu() async {
    final inPip = _ref.read(pipModeProvider);
    final pinned = _ref.read(alwaysOnTopProvider);
    final menu = Menu(
      items: <MenuItem>[
        MenuItem(key: _kShow, label: 'AWAtv pencereyi göster'),
        MenuItem(
          key: _kPip,
          label: inPip
              ? "Picture in picture'dan çık"
              : 'Picture in picture',
        ),
        MenuItem.checkbox(
          key: _kAlwaysOnTop,
          label: 'Pencereyi üstte sabitle',
          checked: pinned,
        ),
        MenuItem.separator(),
        MenuItem(
          key: _kNowPlaying,
          label: _nowPlaying,
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(key: _kQuit, label: "AWAtv'den çık"),
      ],
    );
    try {
      await trayManager.setContextMenu(menu);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[tray] setContextMenu failed: $e');
    }
  }

  // tray_manager calls this when the user left-clicks the icon. macOS
  // would normally pop the menu directly; on Windows a single click does
  // nothing by default, so we synthesise a "show window" gesture.
  @override
  void onTrayIconMouseDown() {
    if (Platform.isWindows) {
      unawaited(_handleShow());
    } else {
      // macOS: open the menu so the user can pick. tray_manager exposes
      // popUpContextMenu which renders next to the status item.
      unawaited(_safePopUpMenu());
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_safePopUpMenu());
  }

  Future<void> _safePopUpMenu() async {
    try {
      await trayManager.popUpContextMenu();
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[tray] popUpContextMenu failed: $e');
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _kShow:
        unawaited(_handleShow());
      case _kPip:
        unawaited(_handlePipToggle());
      case _kAlwaysOnTop:
        unawaited(_handleAlwaysOnTopToggle());
      case _kQuit:
        unawaited(_handleQuit());
      default:
        // disabled / separator — tray_manager still routes these
        break;
    }
  }

  Future<void> _handleShow() async {
    try {
      // If we're hidden in the tray (Windows skip-taskbar mode), restore
      // visibility before focusing. The combined sequence works on both
      // platforms.
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[tray] show failed: $e');
    }
  }

  Future<void> _handlePipToggle() async {
    final controller = _ref.read(pipWindowControllerProvider);
    await controller.toggle();
    // Menu label depends on PiP state — rebuild so the next open shows
    // the correct toggle copy. (The pipModeProvider listener also
    // triggers a rebuild, but rebuilding eagerly here keeps the UX
    // responsive even if the provider notification is debounced.)
    await _publishMenu();
  }

  /// Tray-driven always-on-top toggle.
  ///
  /// The tray surface has no `BuildContext`, so we can't push the
  /// premium-lock sheet directly. Free users see the checkbox flip
  /// momentarily (tray_manager applies the visual state optimistically
  /// before the click handler runs), then we rebuild the menu to snap
  /// it back, raise the main window, and let the in-app surfaces
  /// present the upsell.
  Future<void> _handleAlwaysOnTopToggle() async {
    try {
      final allowed =
          _ref.read(canUseFeatureProvider(PremiumFeature.alwaysOnTop));
      if (!allowed) {
        // Restore the menu so the optimistic check flip reverts, then
        // surface the main window so the user can see the paywall the
        // next time they tap the in-player toggle.
        await _publishMenu();
        await _handleShow();
        return;
      }
      await _ref.read(alwaysOnTopProvider.notifier).toggle();
      // The alwaysOnTopProvider listener rebuilds the menu, but call it
      // explicitly so the next click sees a fresh menu instance even on
      // hosts that batch listener notifications.
      await _publishMenu();
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[tray] always-on-top toggle failed: $e');
    }
  }

  Future<void> _handleQuit() async {
    try {
      await windowManager.destroy();
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[tray] quit failed: $e');
    }
  }
}

/// Riverpod provider that bootstraps the tray and keeps the now-playing
/// label in sync with the active playback context.
///
/// Intentionally created from `main.dart` via `ProviderContainer.read`
/// so the listener on `activePlaybackProvider` is wired before any
/// player route can publish a context.
final systemTrayProvider = Provider<Future<void>>((Ref ref) async {
  if (!isDesktopRuntime()) return;
  await AwaTvTray.initialise(ref);
  ref.onDispose(AwaTvTray.dispose);
});
