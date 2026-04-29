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

/// Toggle always-on-top window pinning. Premium-gated; the host wires
/// the upsell sheet for free users.
class ToggleAlwaysOnTopIntent extends Intent {
  const ToggleAlwaysOnTopIntent();
}

/// Step to the next live channel inside the current pool. Wired to
/// `P` and `Page Down` on desktop.
class ChannelNextIntent extends Intent {
  const ChannelNextIntent();
}

/// Step to the previous live channel. Wired to `Shift+P` and
/// `Page Up` on desktop.
class ChannelPrevIntent extends Intent {
  const ChannelPrevIntent();
}

/// Toggle between the current and last channel. Wired to `L` on
/// desktop. Note: `L` already collides with the YouTube-style
/// "+10s seek" binding at the top of [defaultPlayerShortcuts]; the
/// channel toggle is registered via [Shift+L] to keep the seek
/// shortcut intact.
class ChannelToggleLastIntent extends Intent {
  const ChannelToggleLastIntent();
}

/// Numeric tune-to. [slot] is `0..9`; `0` maps to the 10th channel
/// inside the current pool, matching how a TV remote labels its
/// number row.
class ChannelNumericTuneIntent extends Intent {
  const ChannelNumericTuneIntent(this.slot);
  final int slot;
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
    // Cmd+Shift+T (macOS) / Ctrl+Shift+T (Windows / Linux) toggles
    // always-on-top — matches the muscle memory from reference IPTV
    // apps. We pick a chord with Shift to stay clear of common
    // text-edit shortcuts (Cmd+T opens new tabs in many apps; Cmd+T
    // alone could clash if a future settings screen ever takes focus).
    SingleActivator(
      LogicalKeyboardKey.keyT,
      meta: isMac,
      control: !isMac,
      shift: true,
    ): const ToggleAlwaysOnTopIntent(),
    // Smart channel switcher — TiviMate-style P+/P-/Last toggle.
    // P alone for next, Shift+P for previous (so it stays clear of
    // the existing K/Space play-pause and J/L seek bindings). Page
    // keys mirror the TV-remote experience for users that prefer
    // them.
    const SingleActivator(LogicalKeyboardKey.keyP):
        const ChannelNextIntent(),
    const SingleActivator(LogicalKeyboardKey.keyP, shift: true):
        const ChannelPrevIntent(),
    const SingleActivator(LogicalKeyboardKey.pageDown):
        const ChannelNextIntent(),
    const SingleActivator(LogicalKeyboardKey.pageUp):
        const ChannelPrevIntent(),
    // Last-channel toggle — `L` already maps to "+10s seek" so we
    // claim Shift+L and the dedicated dot key (matches how some
    // TiviMate fork forks expose it on D-pad remotes).
    const SingleActivator(LogicalKeyboardKey.keyL, shift: true):
        const ChannelToggleLastIntent(),
    // Numpad number row — direct tune-to for the first 10 channels
    // in the active pool.
    const SingleActivator(LogicalKeyboardKey.numpad0):
        const ChannelNumericTuneIntent(0),
    const SingleActivator(LogicalKeyboardKey.numpad1):
        const ChannelNumericTuneIntent(1),
    const SingleActivator(LogicalKeyboardKey.numpad2):
        const ChannelNumericTuneIntent(2),
    const SingleActivator(LogicalKeyboardKey.numpad3):
        const ChannelNumericTuneIntent(3),
    const SingleActivator(LogicalKeyboardKey.numpad4):
        const ChannelNumericTuneIntent(4),
    const SingleActivator(LogicalKeyboardKey.numpad5):
        const ChannelNumericTuneIntent(5),
    const SingleActivator(LogicalKeyboardKey.numpad6):
        const ChannelNumericTuneIntent(6),
    const SingleActivator(LogicalKeyboardKey.numpad7):
        const ChannelNumericTuneIntent(7),
    const SingleActivator(LogicalKeyboardKey.numpad8):
        const ChannelNumericTuneIntent(8),
    const SingleActivator(LogicalKeyboardKey.numpad9):
        const ChannelNumericTuneIntent(9),
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
    required this.onToggleAlwaysOnTop,
    this.onChannelNext,
    this.onChannelPrev,
    this.onChannelLast,
    this.onChannelTuneTo,
    super.key,
  });

  final AwaPlayerController? controller;
  final Widget child;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeekRelative;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onExit;

  /// Fired by Cmd/Ctrl+Shift+T. The host runs the premium gate, the
  /// upsell sheet, and the actual `alwaysOnTopProvider.toggle()` call —
  /// this widget just dispatches the intent.
  final VoidCallback onToggleAlwaysOnTop;

  /// TV-remote-style channel switcher hooks. Optional — when null the
  /// matching shortcuts are silently ignored (e.g. on the VOD player
  /// where channel-switching makes no sense).
  final VoidCallback? onChannelNext;
  final VoidCallback? onChannelPrev;
  final VoidCallback? onChannelLast;
  final ValueChanged<int>? onChannelTuneTo;

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
          ToggleAlwaysOnTopIntent:
              CallbackAction<ToggleAlwaysOnTopIntent>(
            onInvoke: (_) {
              widget.onToggleAlwaysOnTop();
              return null;
            },
          ),
          ChannelNextIntent: CallbackAction<ChannelNextIntent>(
            onInvoke: (_) {
              widget.onChannelNext?.call();
              return null;
            },
          ),
          ChannelPrevIntent: CallbackAction<ChannelPrevIntent>(
            onInvoke: (_) {
              widget.onChannelPrev?.call();
              return null;
            },
          ),
          ChannelToggleLastIntent: CallbackAction<ChannelToggleLastIntent>(
            onInvoke: (_) {
              widget.onChannelLast?.call();
              return null;
            },
          ),
          ChannelNumericTuneIntent:
              CallbackAction<ChannelNumericTuneIntent>(
            onInvoke: (ChannelNumericTuneIntent intent) {
              widget.onChannelTuneTo?.call(intent.slot);
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
