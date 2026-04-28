import 'dart:ui';

import 'package:awatv_ui/src/animations/spring_curves.dart';
import 'package:awatv_ui/src/theme/brand_colors.dart';
import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A 64dp persistent player bar that lives at the bottom of the shell.
///
/// Visual primitive only — the navigation rewrite agent wires the player
/// controller, position stream, and casting state. This widget is concerned
/// with:
///
///   * 40x40 thumbnail + title/subtitle column on the left.
///   * Centred transport (prev / play-pause / next) + compact volume.
///   * Trailing slot for cast/pin/expand icons (pluggable).
///   * 2dp progress strip flush against the bottom edge:
///       - VOD     → filled progress (`position / total`).
///       - LIVE    → animated diagonal stripes (no concept of "complete").
///   * Auto-hides itself when [title] is empty AND [thumbnailUrl] is null
///     AND [onPlayPause] is null — i.e. the player is idle.
///
/// The bar layers on a glass surface (24px backdrop blur + brand-tinted
/// fill + hairline outline) so it floats above the content without ever
/// going opaque. Layout is responsive: the title column shrinks first,
/// then volume control collapses below 480px width, then trailing
/// actions fold into a "more" overflow at very narrow widths.
class InlinePlayerBar extends StatelessWidget {
  const InlinePlayerBar({
    required this.title,
    this.subtitle,
    this.thumbnailUrl,
    this.position,
    this.total,
    this.isLive = false,
    this.isPlaying = false,
    this.onPlayPause,
    this.onPrev,
    this.onNext,
    this.volume,
    this.onVolumeChanged,
    this.trailingActions = const <Widget>[],
    this.onExpand,
    super.key,
  });

  /// Primary line — typically the channel/movie title.
  final String title;

  /// Secondary line — programme name, episode label, etc.
  final String? subtitle;

  /// Square channel logo or poster thumbnail.
  final String? thumbnailUrl;

  /// VOD playback position. Ignored when [isLive] is true.
  final Duration? position;

  /// VOD total duration. Ignored when [isLive] is true.
  final Duration? total;

  /// True for live channels — switches the progress strip to the
  /// animated stripe pattern.
  final bool isLive;

  /// Drives the play/pause icon swap.
  final bool isPlaying;

  /// Tap callback for the play/pause button. When null the button is
  /// rendered disabled.
  final VoidCallback? onPlayPause;

  /// Previous track callback. Hidden when null.
  final VoidCallback? onPrev;

  /// Next track callback. Hidden when null.
  final VoidCallback? onNext;

  /// Current volume (0..1). When null the volume control is hidden.
  final double? volume;

  /// Volume change callback. Required when [volume] is supplied.
  final ValueChanged<double>? onVolumeChanged;

  /// Cast / pin / queue actions. Rendered to the right of the
  /// transport on wide screens, or behind a "more" overflow on narrow.
  final List<Widget> trailingActions;

  /// Expand-to-fullscreen callback. Renders the expand icon when set.
  final VoidCallback? onExpand;

  bool get _isEmpty =>
      title.isEmpty && thumbnailUrl == null && onPlayPause == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Auto-hide: shrink to zero height + fade so the surrounding shell
    // can rely on a single widget swap rather than conditional layout.
    return AnimatedSwitcher(
      duration: DesignTokens.motionPanelSlide,
      switchInCurve: curveSpringSoft,
      switchOutCurve: curveSpringSnap,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: _isEmpty
          ? const SizedBox(key: ValueKey<String>('idle'))
          : KeyedSubtree(
              key: const ValueKey<String>('active'),
              child: _Bar(
                title: title,
                subtitle: subtitle,
                thumbnailUrl: thumbnailUrl,
                position: position,
                total: total,
                isLive: isLive,
                isPlaying: isPlaying,
                onPlayPause: onPlayPause,
                onPrev: onPrev,
                onNext: onNext,
                volume: volume,
                onVolumeChanged: onVolumeChanged,
                trailingActions: trailingActions,
                onExpand: onExpand,
                scheme: scheme,
                isDark: isDark,
              ),
            ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.title,
    required this.subtitle,
    required this.thumbnailUrl,
    required this.position,
    required this.total,
    required this.isLive,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.volume,
    required this.onVolumeChanged,
    required this.trailingActions,
    required this.onExpand,
    required this.scheme,
    required this.isDark,
  });

  final String title;
  final String? subtitle;
  final String? thumbnailUrl;
  final Duration? position;
  final Duration? total;
  final bool isLive;
  final bool isPlaying;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final double? volume;
  final ValueChanged<double>? onVolumeChanged;
  final List<Widget> trailingActions;
  final VoidCallback? onExpand;
  final ColorScheme scheme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final glassBg = isDark
        ? BrandColors.glassTintDark
        : BrandColors.glassTintLight;

    return SizedBox(
      height: DesignTokens.persistentPlayerBarHeight,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: DesignTokens.glassBlurStrong,
            sigmaY: DesignTokens.glassBlurStrong,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: glassBg,
              border: Border(
                top: BorderSide(
                  color: scheme.outline.withValues(
                    alpha: DesignTokens.glassBorderAlpha,
                  ),
                  width: 0.5,
                ),
              ),
            ),
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spaceM,
                    DesignTokens.spaceS,
                    DesignTokens.spaceM,
                    DesignTokens.spaceS + 2, // leave room for progress strip
                  ),
                  child: LayoutBuilder(
                    builder: (BuildContext _, BoxConstraints c) {
                      final compact = c.maxWidth < 480;
                      final ultraCompact = c.maxWidth < 360;
                      return Row(
                        children: <Widget>[
                          _Thumb(
                            url: thumbnailUrl,
                            title: title,
                            scheme: scheme,
                          ),
                          const SizedBox(width: DesignTokens.spaceS),
                          Flexible(
                            flex: 3,
                            child: _TitleColumn(
                              title: title,
                              subtitle: subtitle,
                              isLive: isLive,
                              scheme: scheme,
                            ),
                          ),
                          const SizedBox(width: DesignTokens.spaceS),
                          _Transport(
                            isPlaying: isPlaying,
                            onPlayPause: onPlayPause,
                            onPrev: onPrev,
                            onNext: onNext,
                            scheme: scheme,
                          ),
                          if (!compact && volume != null) ...<Widget>[
                            const SizedBox(width: DesignTokens.spaceS),
                            SizedBox(
                              width: 88,
                              child: _Volume(
                                value: volume!,
                                onChanged: onVolumeChanged,
                                scheme: scheme,
                              ),
                            ),
                          ],
                          if (!ultraCompact && trailingActions.isNotEmpty)
                            ...<Widget>[
                              const SizedBox(width: DesignTokens.spaceS),
                              ...trailingActions,
                            ],
                          if (onExpand != null) ...<Widget>[
                            const SizedBox(width: 2),
                            IconButton(
                              tooltip: 'Expand',
                              onPressed: onExpand,
                              icon: const Icon(
                                Icons.open_in_full_rounded,
                                size: 18,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: 2,
                    child: isLive
                        ? _LiveStripeProgress(
                            color: BrandColors.liveAccent,
                            track: scheme.outline.withValues(alpha: 0.4),
                          )
                        : _VodProgress(
                            position: position,
                            total: total,
                            fill: scheme.primary,
                            glow: scheme.secondary,
                            track: scheme.outline.withValues(alpha: 0.4),
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

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.url,
    required this.title,
    required this.scheme,
  });

  final String? url;
  final String title;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      child: Container(
        width: 40,
        height: 40,
        color: scheme.surfaceContainerHighest,
        child: (url == null || url!.isEmpty)
            ? Center(
                child: Text(
                  title.isNotEmpty
                      ? title.characters.first.toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              )
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                fadeInDuration: DesignTokens.motionFast,
              ),
      ),
    );
  }
}

class _TitleColumn extends StatelessWidget {
  const _TitleColumn({
    required this.title,
    required this.subtitle,
    required this.isLive,
    required this.scheme,
  });

  final String title;
  final String? subtitle;
  final bool isLive;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (isLive) ...<Widget>[
              const _LiveDot(color: BrandColors.liveAccent),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.65),
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});
  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext _, Widget? __) {
        final t = _c.value;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4 + 0.4 * t),
                blurRadius: 5 + 5 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.isPlaying,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.scheme,
  });

  final bool isPlaying;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (onPrev != null)
          IconButton(
            tooltip: 'Previous',
            onPressed: onPrev,
            icon: const Icon(Icons.skip_previous_rounded),
            visualDensity: VisualDensity.compact,
            iconSize: 22,
          ),
        _PlayPauseButton(
          isPlaying: isPlaying,
          onPressed: onPlayPause,
          color: scheme.primary,
          fg: scheme.onPrimary,
        ),
        if (onNext != null)
          IconButton(
            tooltip: 'Next',
            onPressed: onNext,
            icon: const Icon(Icons.skip_next_rounded),
            visualDensity: VisualDensity.compact,
            iconSize: 22,
          ),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
    required this.color,
    required this.fg,
  });

  final bool isPlaying;
  final VoidCallback? onPressed;
  final Color color;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: DesignTokens.motionMicroBounce,
          curve: curveSpringSnap,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: onPressed == null
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[color, color.withValues(alpha: 0.78)],
                  ),
            color: onPressed == null ? color.withValues(alpha: 0.3) : null,
            boxShadow: onPressed == null
                ? null
                : <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: AnimatedSwitcher(
            duration: DesignTokens.motionMicroBounce,
            switchInCurve: curveSpringSoft,
            transitionBuilder: (Widget child, Animation<double> a) {
              return ScaleTransition(scale: a, child: child);
            },
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey<bool>(isPlaying),
              size: 22,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _Volume extends StatelessWidget {
  const _Volume({
    required this.value,
    required this.onChanged,
    required this.scheme,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final muted = value <= 0.001;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          muted
              ? Icons.volume_off_rounded
              : value < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
          size: 18,
          color: scheme.onSurface.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: scheme.onSurface,
              inactiveTrackColor:
                  scheme.onSurface.withValues(alpha: 0.18),
              thumbColor: scheme.onSurface,
            ),
            child: Slider(
              value: value.clamp(0, 1),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _VodProgress extends StatelessWidget {
  const _VodProgress({
    required this.position,
    required this.total,
    required this.fill,
    required this.glow,
    required this.track,
  });

  final Duration? position;
  final Duration? total;
  final Color fill;
  final Color glow;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final tot = total?.inMilliseconds ?? 0;
    final pos = position?.inMilliseconds ?? 0;
    final value = tot <= 0 ? 0.0 : (pos / tot).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: track),
        FractionallySizedBox(
          widthFactor: value,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: <Color>[fill, glow]),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveStripeProgress extends StatefulWidget {
  const _LiveStripeProgress({required this.color, required this.track});
  final Color color;
  final Color track;

  @override
  State<_LiveStripeProgress> createState() => _LiveStripeProgressState();
}

class _LiveStripeProgressState extends State<_LiveStripeProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext _, Widget? __) {
        return CustomPaint(
          painter: _StripePainter(
            phase: _c.value,
            color: widget.color,
            track: widget.track,
          ),
        );
      },
    );
  }
}

class _StripePainter extends CustomPainter {
  _StripePainter({
    required this.phase,
    required this.color,
    required this.track,
  });

  final double phase;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = track;
    canvas.drawRect(Offset.zero & size, bg);

    final stripe = Paint()..color = color;
    const stripeWidth = 8.0;
    const gap = 14.0;
    const period = stripeWidth + gap;
    final offset = (phase * period) - period;
    for (var x = offset; x < size.width + period; x += period) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + stripeWidth, 0)
        ..lineTo(x + stripeWidth - size.height, size.height)
        ..lineTo(x - size.height, size.height)
        ..close();
      canvas.drawPath(path, stripe);
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) =>
      old.phase != phase || old.color != color || old.track != track;
}
