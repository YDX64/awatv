import 'dart:ui';

import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A horizontal channel row: 16:9 logo on the left, name + EPG strip on
/// the right, and a thin "now playing" progress bar at the bottom.
///
/// Designed to live in a `ListView` of live channels. Glass background
/// makes it feel premium without dominating attention.
class ChannelTile extends StatefulWidget {
  const ChannelTile({
    required this.name,
    this.logoUrl,
    this.nowPlaying,
    this.nextProgramme,
    this.group,
    this.progress,
    this.isLive = true,
    this.isFavorite = false,
    this.onTap,
    this.onLongPress,
    this.onFavoriteToggle,
    this.heroTag,
    super.key,
  });

  /// Channel name.
  final String name;

  /// Logo URL — typically square or 16:9. Falls back to a brand chip.
  final String? logoUrl;

  /// Title of the currently airing programme.
  final String? nowPlaying;

  /// Title of the next-up programme.
  final String? nextProgramme;

  /// Optional group/category label, used as a fallback subtitle when no
  /// EPG data is available (e.g. "Sports", "News HD").
  final String? group;

  /// Live progress, 0..1. Hidden when null.
  final double? progress;

  /// Adds the red "LIVE" pulse next to the name.
  final bool isLive;

  /// Whether the channel is favourited; renders a filled heart.
  final bool isFavorite;

  /// Tap callback (open player).
  final VoidCallback? onTap;

  /// Long-press callback — typically opens a context menu (favourite,
  /// add to home, share).
  final VoidCallback? onLongPress;

  /// Heart toggle callback. When null the heart is hidden.
  final VoidCallback? onFavoriteToggle;

  /// Hero tag for the logo flight to a player/details screen.
  final String? heroTag;

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: DesignTokens.motionFast,
    upperBound: 0.03,
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down(_) {
    if (widget.onTap == null) return;
    _press.forward();
  }

  void _up(_) {
    if (widget.onTap == null) return;
    _press.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    final glassBase = isDark
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.85);

    Widget logo = AspectRatio(
      aspectRatio: DesignTokens.channelTileAspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        child: _ChannelLogo(
          logoUrl: widget.logoUrl,
          name: widget.name,
          surface: scheme.surfaceContainerHighest,
          primary: scheme.primary,
          onSurface: scheme.onSurface,
        ),
      ),
    );

    if (widget.heroTag != null) {
      logo = Hero(tag: widget.heroTag!, child: logo);
    }

    return Semantics(
      button: widget.onTap != null,
      label: widget.name,
      value: widget.nowPlaying,
      child: AnimatedBuilder(
        animation: _press,
        builder: (BuildContext context, Widget? child) {
          return Transform.scale(
            scale: 1 - _press.value,
            child: child,
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: _down,
          onTapUp: _up,
          onTapCancel: () => _press.reverse(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DesignTokens.radiusL),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: DesignTokens.blurLow,
                sigmaY: DesignTokens.blurLow,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: glassBase,
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusL),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.35),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DesignTokens.spaceM,
                        DesignTokens.spaceM,
                        DesignTokens.spaceM,
                        DesignTokens.spaceS,
                      ),
                      child: Row(
                        children: <Widget>[
                          SizedBox(width: 96, child: logo),
                          const SizedBox(width: DesignTokens.spaceM),
                          Expanded(
                            child: _ChannelMeta(
                              name: widget.name,
                              nowPlaying: widget.nowPlaying,
                              nextProgramme: widget.nextProgramme,
                              isLive: widget.isLive,
                              text: text,
                              scheme: scheme,
                            ),
                          ),
                          if (widget.onFavoriteToggle != null) ...<Widget>[
                            const SizedBox(width: DesignTokens.spaceS),
                            _FavoriteButton(
                              active: widget.isFavorite,
                              onPressed: widget.onFavoriteToggle!,
                              accent: scheme.primary,
                              idle: scheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _ProgressStrip(
                      value: widget.progress,
                      track: scheme.outline.withValues(alpha: 0.35),
                      fill: scheme.primary,
                      glow: scheme.secondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({
    required this.logoUrl,
    required this.name,
    required this.surface,
    required this.primary,
    required this.onSurface,
  });

  final String? logoUrl;
  final String name;
  final Color surface;
  final Color primary;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    if (logoUrl == null || logoUrl!.isEmpty) {
      return _LogoPlaceholder(
        name: name,
        surface: surface,
        primary: primary,
        onSurface: onSurface,
      );
    }
    return Container(
      color: surface,
      padding: const EdgeInsets.all(DesignTokens.spaceXs),
      child: CachedNetworkImage(
        imageUrl: logoUrl!,
        fit: BoxFit.contain,
        fadeInDuration: DesignTokens.motionFast,
        placeholder: (BuildContext _, String __) =>
            const SizedBox.expand(),
        errorWidget: (BuildContext _, String __, Object ___) =>
            _LogoPlaceholder(
          name: name,
          surface: surface,
          primary: primary,
          onSurface: onSurface,
        ),
      ),
    );
  }
}

class _LogoPlaceholder extends StatelessWidget {
  const _LogoPlaceholder({
    required this.name,
    required this.surface,
    required this.primary,
    required this.onSurface,
  });
  final String name;
  final Color surface;
  final Color primary;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            primary.withValues(alpha: 0.35),
            surface,
          ],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 0.4,
            color: onSurface,
          ),
        ),
      ),
    );
  }

  static String _initials(String value) {
    final tokens = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return '?';
    if (tokens.length == 1) {
      return tokens.first.characters.first.toUpperCase();
    }
    return (tokens.first.characters.first + tokens[1].characters.first)
        .toUpperCase();
  }
}

class _ChannelMeta extends StatelessWidget {
  const _ChannelMeta({
    required this.name,
    required this.nowPlaying,
    required this.nextProgramme,
    required this.isLive,
    required this.text,
    required this.scheme,
  });

  final String name;
  final String? nowPlaying;
  final String? nextProgramme;
  final bool isLive;
  final TextTheme text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (isLive) ...<Widget>[
              _LivePulse(color: scheme.error),
              const SizedBox(width: DesignTokens.spaceS),
            ],
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium,
              ),
            ),
          ],
        ),
        if (nowPlaying != null && nowPlaying!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            nowPlaying!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
        if (nextProgramme != null && nextProgramme!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            'Next · ${nextProgramme!}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ],
    );
  }
}

class _LivePulse extends StatefulWidget {
  const _LivePulse({required this.color});
  final Color color;

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext _, Widget? __) {
        final t = _controller.value;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4 + 0.3 * t),
                blurRadius: 6 + 6 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({
    required this.value,
    required this.track,
    required this.fill,
    required this.glow,
  });
  final double? value;
  final Color track;
  final Color fill;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return const SizedBox(height: DesignTokens.spaceXs);
    }
    final clamped = value!.clamp(0.0, 1.0);
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (BuildContext _, BoxConstraints constraints) {
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ColoredBox(color: track),
              FractionallySizedBox(
                widthFactor: clamped,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[fill, glow],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({
    required this.active,
    required this.onPressed,
    required this.accent,
    required this.idle,
  });
  final bool active;
  final VoidCallback onPressed;
  final Color accent;
  final Color idle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: active ? 'Remove from favourites' : 'Add to favourites',
      icon: AnimatedSwitcher(
        duration: DesignTokens.motionFast,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return ScaleTransition(scale: animation, child: child);
        },
        child: Icon(
          active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey<bool>(active),
          color: active ? accent : idle,
          size: 22,
        ),
      ),
    );
  }
}
