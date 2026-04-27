import 'dart:io' show Platform;

import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// macOS hides its titlebar via `TitleBarStyle.hidden`, but the traffic
/// lights still occupy the top-left corner. We reserve this much space
/// before our own widgets start drawing so they never collide.
const double _macTrafficLightInset = 78;

/// Width of the Windows caption-button cluster (min, max, close) we draw
/// ourselves. Matches Microsoft's recommended 46pt-per-button caption.
const double _windowsCaptionWidth = 46.0 * 3;

/// Total height of the desktop chrome bar. 32 is the minimum hit target
/// where double-click-to-maximize feels natural on Windows; macOS uses
/// the same so the layout stays consistent across platforms.
const double _chromeHeight = 32;

/// Wraps the entire app and prepends a slim, drag-enabled chrome bar.
///
/// What lives here:
///   * a draggable region that calls `windowManager.startDragging()`
///     (so the user can grab anywhere on the bar to move the window),
///   * a double-click-to-maximize affordance,
///   * the app title centered,
///   * platform-specific caption controls on Windows (min / max / close),
///   * empty space on the macOS leading edge so traffic lights stay
///     unobstructed.
///
/// Renders as a no-op when the app is mounted on a non-desktop platform —
/// the wrapper in `awa_tv_app.dart` already guards on
/// `isDesktopFormProvider`, so reaching this widget on mobile would be a
/// programming error, but we soft-fail to be safe.
class DesktopChrome extends ConsumerWidget {
  const DesktopChrome({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = ref.watch(isDesktopFormProvider);
    if (!isDesktop) return child;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isMac = Platform.isMacOS;

    return Material(
      color: scheme.surface,
      child: Column(
        children: <Widget>[
          _ChromeBar(
            scheme: scheme,
            leadingInset: isMac ? _macTrafficLightInset : 8,
            trailing: isMac
                ? const SizedBox.shrink()
                : const _WindowsCaptionButtons(),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ChromeBar extends StatelessWidget {
  const _ChromeBar({
    required this.scheme,
    required this.leadingInset,
    required this.trailing,
  });

  final ColorScheme scheme;
  final double leadingInset;
  final Widget trailing;

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _chromeHeight,
      child: ColoredBox(
        // Slightly elevated tint over surface so the chrome reads as
        // "system" rather than "content".
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.04),
          scheme.surface,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // `onPanStart` is the platform-correct handle for "start
          // dragging the window" — `onTapDown` would also work but pan
          // gives us cleaner hit-testing against captions.
          onPanStart: (_) => windowManager.startDragging(),
          onDoubleTap: _toggleMaximize,
          child: Row(
            children: <Widget>[
              SizedBox(width: leadingInset),
              const _AppBadge(),
              const Spacer(),
              _Title(scheme: scheme),
              const Spacer(),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _AppBadge extends StatelessWidget {
  const _AppBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.live_tv_rounded,
            size: 16,
            color: scheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            'AWAtv',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: scheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // Kept intentionally subtle — the app's main visual identity lives
    // inside the home shell, not the chrome.
    return Text(
      '',
      style: TextStyle(
        fontSize: 12,
        color: scheme.onSurface.withValues(alpha: 0.55),
      ),
    );
  }
}

/// Custom caption buttons drawn on Windows. We draw our own (rather than
/// asking `windowManager` for a native bar) so the chrome can host the
/// app title and stay theme-aware.
///
/// Behaviour:
///   * Minimize hides to the taskbar.
///   * Maximize toggles between maximized/restored.
///   * Close ends the app — `windowManager.close()` honours platform
///     conventions (sends `WM_CLOSE`).
class _WindowsCaptionButtons extends StatefulWidget {
  const _WindowsCaptionButtons();

  @override
  State<_WindowsCaptionButtons> createState() =>
      _WindowsCaptionButtonsState();
}

class _WindowsCaptionButtonsState extends State<_WindowsCaptionButtons>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refreshMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refreshMaximized() async {
    final m = await windowManager.isMaximized();
    if (!mounted) return;
    setState(() => _maximized = m);
  }

  @override
  void onWindowMaximize() => _refreshMaximized();

  @override
  void onWindowUnmaximize() => _refreshMaximized();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _windowsCaptionWidth,
      height: _chromeHeight,
      child: Row(
        children: <Widget>[
          _CaptionButton(
            tooltip: 'Kucult',
            icon: Icons.minimize,
            onTap: windowManager.minimize,
          ),
          _CaptionButton(
            tooltip: _maximized ? 'Geri al' : 'Buyut',
            icon: _maximized
                ? Icons.filter_none_outlined
                : Icons.crop_square,
            onTap: () async {
              if (_maximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _CaptionButton(
            tooltip: 'Kapat',
            icon: Icons.close,
            onTap: windowManager.close,
            danger: true,
          ),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hoverColor = widget.danger
        ? const Color(0xFFE81123)
        : scheme.onSurface.withValues(alpha: 0.08);
    final iconColor = _hover && widget.danger
        ? Colors.white
        : scheme.onSurface.withValues(alpha: 0.8);

    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Tooltip(
            message: widget.tooltip,
            child: ColoredBox(
              color: _hover ? hoverColor : Colors.transparent,
              child: Center(
                child: Icon(widget.icon, size: 14, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
