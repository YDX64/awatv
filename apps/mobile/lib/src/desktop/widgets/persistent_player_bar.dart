import 'dart:ui';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/desktop/always_on_top.dart';
import 'package:awatv_mobile/src/desktop/widgets/now_playing_state.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// IPTV-Expert-class persistent mini player bar.
///
/// Pinned to the bottom of the desktop content pane. Hidden when nothing
/// is playing (animated reveal/dismiss); reveals smoothly when
/// [nowPlayingProvider] starts emitting non-null state.
///
/// Layout:
/// ┌────────────────────────────────────────────────────────────────────┐
/// │ [40x40 thumb] Title              [▶] [⏭] [🔊]──[bar]── [📡][📌][⛶]│
/// │                Subtitle                                            │
/// │ ─── progress (1px) ───                                            │
/// └────────────────────────────────────────────────────────────────────┘
class PersistentPlayerBar extends ConsumerWidget {
  const PersistentPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nowPlayingProvider);

    return AnimatedSwitcher(
      duration: DesignTokens.motionPanelSlide,
      switchInCurve: Curves.easeOutQuint,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> anim) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      child: state == null
          ? const SizedBox.shrink(key: ValueKey<String>('hidden'))
          : _Bar(
              key: const ValueKey<String>('visible'),
              state: state,
            ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.state, super.key});

  final NowPlaying state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgAlpha = isDark
        ? DesignTokens.glassBgAlphaDark
        : DesignTokens.glassBgAlphaLight;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: DesignTokens.glassBlurStrong,
          sigmaY: DesignTokens.glassBlurStrong,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest
                .withValues(alpha: bgAlpha + 0.05),
            border: Border(
              top: BorderSide(
                color: scheme.outline.withValues(alpha: 0.18),
              ),
            ),
          ),
          child: SizedBox(
            height: DesignTokens.persistentPlayerBarHeight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _ProgressLine(state: state),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spaceM,
                    ),
                    child: Row(
                      children: <Widget>[
                        _Thumb(state: state),
                        const SizedBox(width: DesignTokens.spaceM),
                        Expanded(child: _Titles(state: state)),
                        const SizedBox(width: DesignTokens.spaceM),
                        _TransportControls(state: state),
                        const SizedBox(width: DesignTokens.spaceS),
                        _RightControls(state: state),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.state});

  final NowPlaying state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (state.isLive) {
      // Live — striped pattern walking left-to-right. Matches the IPTV
      // "live indicator" affordance without copying any specific design.
      return SizedBox(
        height: 2,
        child: _LiveStripes(color: scheme.secondary),
      );
    }
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        value: state.progress,
        backgroundColor: scheme.outline.withValues(alpha: 0.25),
        valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
      ),
    );
  }
}

class _LiveStripes extends StatefulWidget {
  const _LiveStripes({required this.color});
  final Color color;

  @override
  State<_LiveStripes> createState() => _LiveStripesState();
}

class _LiveStripesState extends State<_LiveStripes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext _, Widget? __) {
        return CustomPaint(
          painter: _StripePainter(
            color: widget.color,
            phase: _ctrl.value,
          ),
        );
      },
    );
  }
}

class _StripePainter extends CustomPainter {
  _StripePainter({required this.color, required this.phase});

  final Color color;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    const stripeWidth = 12.0;
    final offset = phase * stripeWidth;
    for (var x = -stripeWidth + offset;
        x < size.width + stripeWidth;
        x += stripeWidth) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + stripeWidth * 0.6, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StripePainter old) =>
      old.phase != phase || old.color != color;
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.state});

  final NowPlaying state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = DesignTokens.persistentPlayerThumbSize;
    final hasUrl = state.thumbnailUrl != null && state.thumbnailUrl!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      child: Container(
        width: size,
        height: size,
        color: scheme.surface,
        alignment: Alignment.center,
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: state.thumbnailUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                fadeInDuration: DesignTokens.motionFast,
                errorWidget: (BuildContext _, String __, Object ___) =>
                    _fallbackIcon(scheme),
              )
            : _fallbackIcon(scheme),
      ),
    );
  }

  Widget _fallbackIcon(ColorScheme scheme) {
    final IconData icon;
    switch (state.kind) {
      case HistoryKind.live:
        icon = Icons.live_tv_rounded;
      case HistoryKind.vod:
        icon = Icons.movie_outlined;
      case HistoryKind.series:
        icon = Icons.video_library_outlined;
    }
    return Icon(icon, size: 18, color: scheme.onSurface.withValues(alpha: 0.6));
  }
}

class _Titles extends StatelessWidget {
  const _Titles({required this.state});

  final NowPlaying state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (state.isLive) ...<Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusS),
                ),
                child: Text(
                  'CANLI',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: scheme.secondary,
                  ),
                ),
              ),
              const SizedBox(width: DesignTokens.spaceS),
            ],
            Expanded(
              child: Text(
                state.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (state.subtitle != null && state.subtitle!.isNotEmpty)
          Text(
            state.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
      ],
    );
  }
}

class _TransportControls extends ConsumerWidget {
  const _TransportControls({required this.state});

  final NowPlaying state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _IconBtn(
          icon: Icons.skip_previous_rounded,
          tooltip: 'Onceki',
          // Stub — neighbouring item nav requires player package wiring.
          // Hide until the player feature exposes a callback.
          onTap: null,
        ),
        _IconBtn(
          icon: state.isPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          tooltip: state.isPlaying ? 'Duraklat' : 'Oynat',
          accent: true,
          onTap: () =>
              ref.read(nowPlayingProvider.notifier).togglePlay(),
        ),
        _IconBtn(
          icon: Icons.skip_next_rounded,
          tooltip: 'Sonraki',
          onTap: null,
        ),
      ],
    );
  }
}

class _RightControls extends ConsumerWidget {
  const _RightControls({required this.state});

  final NowPlaying state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(alwaysOnTopProvider);
    final itemId = state.itemId;

    // Detail / fullscreen routing leans on `itemId` — the bar can deep
    // link to /channel/:id or /movie/:id without the full PlayerLaunchArgs
    // payload. When no id is set we hide the button to avoid the
    // defensive PlayerArgError fallback in the router.
    String? expandRoute() {
      if (itemId == null || itemId.isEmpty) return null;
      switch (state.kind) {
        case HistoryKind.live:
          return '/channel/$itemId';
        case HistoryKind.vod:
          return '/movie/$itemId';
        case HistoryKind.series:
          return '/series/$itemId';
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _IconBtn(
          icon: Icons.cast_rounded,
          tooltip: 'Yayinla',
          // Cast UI lives in the player package; until that feature
          // exposes a "switch device" callback we leave this disabled
          // rather than open a half-broken sheet.
          onTap: null,
        ),
        _IconBtn(
          icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
          tooltip: pinned ? 'Ust katmandan kaldir' : 'En ustte tut',
          accent: pinned,
          onTap: () =>
              ref.read(alwaysOnTopProvider.notifier).toggle(),
        ),
        _IconBtn(
          icon: Icons.open_in_full_rounded,
          tooltip: 'Detay sayfasini ac',
          onTap: expandRoute() == null
              ? null
              : () => context.push(expandRoute()!),
        ),
        _IconBtn(
          icon: Icons.close_rounded,
          tooltip: 'Kapat',
          onTap: () => ref.read(nowPlayingProvider.notifier).clear(),
        ),
      ],
    );
  }
}

class _IconBtn extends StatefulWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool accent;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = widget.onTap == null;
    final fg = disabled
        ? scheme.onSurface.withValues(alpha: 0.30)
        : widget.accent
            ? scheme.primary
            : _hover
                ? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.75);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: disabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: DesignTokens.motionFast,
            curve: Curves.easeOut,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _hover && !disabled
                  ? scheme.onSurface.withValues(alpha: 0.08)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 18, color: fg),
          ),
        ),
      ),
    );
  }
}
