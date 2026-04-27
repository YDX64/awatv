import 'dart:io' show Platform;

import 'package:awatv_player/awatv_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Intent fired when the user wants to toggle play/pause.
class TogglePlayIntent extends Intent {
  const TogglePlayIntent();
}

/// Intent fired when the user wants to seek by a relative amount.
/// Positive values advance, negatives rewind.
class SeekRelativeIntent extends Intent {
  const SeekRelativeIntent(this.delta);
  final Duration delta;
}

/// Volume nudge. `delta` is on a 0..100 scale.
class VolumeChangeIntent extends Intent {
  const VolumeChangeIntent(this.delta);
  final double delta;
}

/// Toggle mute on/off.
class ToggleMuteIntent extends Intent {
  const ToggleMuteIntent();
}

/// Toggle fullscreen via `window_manager.setFullScreen`.
class ToggleFullscreenIntent extends Intent {
  const ToggleFullscreenIntent();
}

/// Close the current player route, exiting fullscreen first if needed.
class ExitPlayerIntent extends Intent {
  const ExitPlayerIntent();
}

/// Close the OS window entirely (Cmd/Ctrl+W).
class CloseWindowIntent extends Intent {
  const CloseWindowIntent();
}

/// Quit the application (Cmd+Q on macOS).
class QuitAppIntent extends Intent {
  const QuitAppIntent();
}

/// Default shortcut bindings used by the player on desktop.
///
/// Centralised so the table is auditable in one place — see the report
/// in this PR for the human-readable mapping.
Map<ShortcutActivator, Intent> defaultPlayerShortcuts() {
  final isMac = Platform.isMacOS;
  return <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.space): const TogglePlayIntent(),
    const SingleActivator(LogicalKeyboardKey.keyK): const TogglePlayIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const SeekRelativeIntent(Duration(seconds: -10)),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const SeekRelativeIntent(Duration(seconds: 10)),
    const SingleActivator(LogicalKeyboardKey.keyJ):
        const SeekRelativeIntent(Duration(seconds: -10)),
    const SingleActivator(LogicalKeyboardKey.keyL):
        const SeekRelativeIntent(Duration(seconds: 10)),
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const VolumeChangeIntent(5),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const VolumeChangeIntent(-5),
    const SingleActivator(LogicalKeyboardKey.keyM): const ToggleMuteIntent(),
    const SingleActivator(LogicalKeyboardKey.keyF):
        const ToggleFullscreenIntent(),
    // Some apps use F11 for fullscreen on Windows.
    const SingleActivator(LogicalKeyboardKey.f11):
        const ToggleFullscreenIntent(),
    const SingleActivator(LogicalKeyboardKey.escape):
        const ExitPlayerIntent(),
    SingleActivator(LogicalKeyboardKey.keyW, meta: isMac, control: !isMac):
        const CloseWindowIntent(),
    if (isMac)
      const SingleActivator(LogicalKeyboardKey.keyQ, meta: true):
          const QuitAppIntent(),
  };
}

/// Wraps the player with desktop keyboard shortcuts.
///
/// The widget is intentionally generic over the player controller — it
/// only needs the parent to wire up the four high-level callbacks. This
/// keeps the player state owned by `PlayerScreen` and avoids leaking
/// stream subscriptions across widget boundaries.
///
/// Usage in `PlayerScreen.build()`:
/// ```dart
/// child = DesktopPlayerShortcuts(
///   controller: _controller,
///   onTogglePlay: _togglePlay,
///   onSeekRelative: _seekRelative,
///   onToggleFullscreen: _toggleFullscreen,
///   onExit: () => context.pop(),
///   child: ...,
/// );
/// ```
class DesktopPlayerShortcuts extends StatefulWidget {
  const DesktopPlayerShortcuts({
    required this.controller,
    required this.child,
    required this.onTogglePlay,
    required this.onSeekRelative,
    required this.onToggleFullscreen,
    required this.onExit,
    super.key,
  });

  final AwaPlayerController? controller;
  final Widget child;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeekRelative;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onExit;

  @override
  State<DesktopPlayerShortcuts> createState() =>
      _DesktopPlayerShortcutsState();
}

class _DesktopPlayerShortcutsState extends State<DesktopPlayerShortcuts> {
  /// Mirror of the libmpv volume state. `setVolume` accepts 0..100.
  double _volume = 100;
  double _mutedVolume = 100;
  bool _muted = false;

  Future<void> _adjustVolume(double delta) async {
    final c = widget.controller;
    if (c == null) return;
    _volume = (_volume + delta).clamp(0, 100).toDouble();
    if (_muted && _volume > 0) _muted = false;
    await c.setVolume(_volume);
    setState(() {});
  }

  Future<void> _toggleMute() async {
    final c = widget.controller;
    if (c == null) return;
    if (_muted) {
      await c.setVolume(_mutedVolume);
      _volume = _mutedVolume;
      _muted = false;
    } else {
      _mutedVolume = _volume;
      await c.setVolume(0);
      _volume = 0;
      _muted = true;
    }
    setState(() {});
  }

  Future<void> _closeWindow() async {
    await windowManager.close();
  }

  Future<void> _quitApp() async {
    // `windowManager.destroy()` skips onWindowClose handlers — closer to
    // a Cmd+Q than a polite close. Safe because we save geometry on
    // resize/move events, not close.
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: defaultPlayerShortcuts(),
      child: Actions(
        actions: <Type, Action<Intent>>{
          TogglePlayIntent: CallbackAction<TogglePlayIntent>(
            onInvoke: (_) {
              widget.onTogglePlay();
              return null;
            },
          ),
          SeekRelativeIntent: CallbackAction<SeekRelativeIntent>(
            onInvoke: (SeekRelativeIntent intent) {
              widget.onSeekRelative(intent.delta);
              return null;
            },
          ),
          VolumeChangeIntent: CallbackAction<VolumeChangeIntent>(
            onInvoke: (VolumeChangeIntent intent) {
              _adjustVolume(intent.delta);
              return null;
            },
          ),
          ToggleMuteIntent: CallbackAction<ToggleMuteIntent>(
            onInvoke: (_) {
              _toggleMute();
              return null;
            },
          ),
          ToggleFullscreenIntent: CallbackAction<ToggleFullscreenIntent>(
            onInvoke: (_) {
              widget.onToggleFullscreen();
              return null;
            },
          ),
          ExitPlayerIntent: CallbackAction<ExitPlayerIntent>(
            onInvoke: (_) async {
              if (await windowManager.isFullScreen()) {
                await windowManager.setFullScreen(false);
                return null;
              }
              widget.onExit();
              return null;
            },
          ),
          CloseWindowIntent: CallbackAction<CloseWindowIntent>(
            onInvoke: (_) {
              _closeWindow();
              return null;
            },
          ),
          QuitAppIntent: CallbackAction<QuitAppIntent>(
            onInvoke: (_) {
              _quitApp();
              return null;
            },
          ),
        },
        // `autofocus` so a freshly pushed player route immediately
        // receives keystrokes — without it the user has to click first.
        child: Focus(
          autofocus: true,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Helper used by the player screen to flip the OS window's fullscreen
/// state. Pulled out so the player doesn't import `window_manager`
/// directly — keeps the desktop dependency contained.
Future<void> toggleDesktopFullscreen() async {
  final isFs = await windowManager.isFullScreen();
  await windowManager.setFullScreen(!isFs);
}
