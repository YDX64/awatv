import 'dart:io' show Platform;
import 'dart:ui';

import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';

/// Hive box that stores the window's last known geometry. Opened lazily by
/// [initialiseDesktopWindow]; the same box is reused on subsequent boots.
const String _windowPrefsBox = 'desktop_window_prefs';
const String _kWidth = 'w';
const String _kHeight = 'h';
const String _kX = 'x';
const String _kY = 'y';
const String _kMaximized = 'max';

/// The default window size we open at on first launch — tuned for a
/// 1280x800 MacBook 13" display so the chrome and adaptive home shell
/// (which switches at 1100dp) both have room to breathe.
const Size _defaultSize = Size(1280, 800);
const Size _minSize = Size(800, 600);

/// One-shot setup for the desktop window manager.
///
/// Called from `main()` *only* on desktop platforms. Boots
/// `window_manager`, applies the persisted geometry (if any), and shows
/// the window. macOS gets a hidden titlebar so we can paint our own
/// chrome flush with the traffic-light buttons; Windows keeps its native
/// titlebar (we render extra content beneath it).
Future<void> initialiseDesktopWindow() async {
  if (!isDesktopRuntime()) return;

  await windowManager.ensureInitialized();

  final saved = await _readSavedGeometry();
  final size = saved.size ?? _defaultSize;
  final position = saved.position;
  final maximized = saved.maximized;

  final options = WindowOptions(
    size: size,
    minimumSize: _minSize,
    center: position == null,
    backgroundColor: const Color(0x00000000),
    skipTaskbar: false,
    titleBarStyle: Platform.isMacOS
        ? TitleBarStyle.hidden
        : TitleBarStyle.normal,
    title: 'AWAtv',
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    if (position != null) {
      await windowManager.setBounds(
        Rect.fromLTWH(
          position.dx,
          position.dy,
          size.width,
          size.height,
        ),
      );
    }
    if (maximized) {
      await windowManager.maximize();
    }
    await windowManager.show();
    await windowManager.focus();
  });

  // Persist geometry on every relevant event. We attach a single listener
  // that writes back to the prefs box; debouncing isn't worth the
  // complexity given Hive boxes are append-only and very cheap.
  windowManager.addListener(_DesktopWindowListener());
}

/// Internal record of what we read back from Hive on boot.
class _SavedGeometry {
  const _SavedGeometry({this.size, this.position, this.maximized = false});
  final Size? size;
  final Offset? position;
  final bool maximized;
}

Future<_SavedGeometry> _readSavedGeometry() async {
  try {
    final box = await Hive.openBox<dynamic>(_windowPrefsBox);
    final w = (box.get(_kWidth) as num?)?.toDouble();
    final h = (box.get(_kHeight) as num?)?.toDouble();
    final x = (box.get(_kX) as num?)?.toDouble();
    final y = (box.get(_kY) as num?)?.toDouble();
    final max = box.get(_kMaximized) as bool? ?? false;

    Size? size;
    if (w != null && h != null && w >= _minSize.width && h >= _minSize.height) {
      size = Size(w, h);
    }
    Offset? position;
    if (x != null && y != null) {
      position = Offset(x, y);
    }
    return _SavedGeometry(size: size, position: position, maximized: max);
  } on Object catch (e) {
    if (kDebugMode) {
      // print() is the simplest way to surface boot diagnostics before
      // any logger has been wired up.
      // ignore: avoid_print
      print('[desktop_window] could not read prefs: $e');
    }
    return const _SavedGeometry();
  }
}

Future<void> _persistGeometry() async {
  try {
    final box = await Hive.openBox<dynamic>(_windowPrefsBox);
    final maximized = await windowManager.isMaximized();
    if (maximized) {
      // Don't overwrite the restorable size; just note the flag.
      await box.put(_kMaximized, true);
      return;
    }
    final bounds = await windowManager.getBounds();
    await box.putAll(<String, dynamic>{
      _kWidth: bounds.width,
      _kHeight: bounds.height,
      _kX: bounds.left,
      _kY: bounds.top,
      _kMaximized: false,
    });
  } on Object catch (e) {
    if (kDebugMode) {
      // print() is the simplest way to surface diagnostics from a hot
      // path that runs before our logger is initialised.
      // ignore: avoid_print
      print('[desktop_window] could not persist prefs: $e');
    }
  }
}

/// Listens for window-level events and writes geometry back to Hive.
///
/// We deliberately avoid a tight `onWindowMove` write loop on Windows
/// (which fires per-pixel) by only persisting on resize/maximize/restore
/// and on close. The trade-off: if the user only moves and then crashes
/// before any other event, we lose the new position — acceptable.
class _DesktopWindowListener extends WindowListener {
  @override
  void onWindowResize() {
    _persistGeometry();
  }

  @override
  void onWindowMaximize() {
    _persistGeometry();
  }

  @override
  void onWindowUnmaximize() {
    _persistGeometry();
  }

  @override
  void onWindowClose() {
    _persistGeometry();
  }

  @override
  void onWindowMoved() {
    // Cheap on macOS (single event per drag end), noisy on Windows. Still
    // worth it: window position drift between sessions is annoying.
    _persistGeometry();
  }
}
