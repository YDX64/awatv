import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:awatv_ui/src/widgets/gradient_scrim.dart';
import 'package:awatv_ui/src/widgets/rating_pill.dart';
import 'package:awatv_ui/src/widgets/shimmer_skeleton.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A 2:3 movie/series poster card.
///
/// Renders the artwork with a legibility scrim, an overlaid rating pill,
/// and a title strip below. Includes:
///   - Hero animation when [heroTag] is supplied.
///   - Spring-style press scale (0.96) for tactile feedback.
///   - Shimmer loading state and graceful gradient placeholder on error.
class PosterCard extends StatefulWidget {
  const PosterCard({
    required this.title,
    this.imageUrl,
    this.posterUrl,
    this.rating,
    this.year,
    this.subtitle,
    this.onTap,
    this.heroTag,
    this.width,
    this.showCaption = true,
    super.key,
  });

  /// Title label, also used as fallback initial when no image URL is set.
  final String title;

  /// Remote URL. Either [imageUrl] or [posterUrl] is acceptable; when both
  /// are null/empty the gradient placeholder is rendered.
  final String? imageUrl;

  /// Alias for [imageUrl] — accepted because most call sites store
  /// posters under a `posterUrl` field.
  final String? posterUrl;

  /// 0–10 score; renders a rating pill when supplied.
  final double? rating;

  /// Release year, displayed under the title.
  final int? year;

  /// Optional secondary line replacing the year (e.g. genres).
  final String? subtitle;

  /// Tap callback.
  final VoidCallback? onTap;

  /// When non-null, the poster image is wrapped in a `Hero` for a smooth
  /// flight to a detail screen.
  final String? heroTag;

  /// Optional explicit width — useful inside horizontally scrolling rails.
  final double? width;

  /// Toggle the title/year caption strip below the artwork.
  final bool showCaption;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: DesignTokens.motionFast,
    lowerBound: 0,
    upperBound: 0.04,
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
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    Widget artwork = AspectRatio(
      aspectRatio: DesignTokens.posterAspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        child: GradientScrim(
          intensity: 0.85,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _PosterImage(
                imageUrl: widget.imageUrl,
                title: widget.title,
                primary: scheme.primary,
                secondary: scheme.secondary,
                surface: scheme.surfaceContainerHighest,
                onSurface: scheme.onSurface,
              ),
              if (widget.rating != null)
                Positioned(
                  top: DesignTokens.spaceS,
                  right: DesignTokens.spaceS,
                  child: RatingPill(rating: widget.rating!),
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.heroTag != null) {
      artwork = Hero(
        tag: widget.heroTag!,
        child: artwork,
      );
    }

    final Widget caption = widget.showCaption
        ? Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spaceS),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else if (widget.year != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.year!.toString(),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();

    return Semantics(
      button: widget.onTap != null,
      label: widget.title,
      value: widget.year?.toString(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (BuildContext context, Widget? child) {
          return Transform.scale(
            scale: 1 - _press.value,
            child: child,
          );
        },
        child: SizedBox(
          width: widget.width,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown: _down,
            onTapUp: _up,
            onTapCancel: () => _press.reverse(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                artwork,
                if (widget.showCaption) caption,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({
    required this.imageUrl,
    required this.title,
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.onSurface,
  });

  final String? imageUrl;
  final String title;
  final Color primary;
  final Color secondary;
  final Color surface;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _Placeholder(
        title: title,
        primary: primary,
        secondary: secondary,
        surface: surface,
        onSurface: onSurface,
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      fadeInDuration: DesignTokens.motionMedium,
      fadeOutDuration: DesignTokens.motionFast,
      placeholder: (BuildContext _, String __) => ShimmerSkeleton.box(
        radius: 0,
      ),
      errorWidget: (BuildContext _, String __, Object ___) => _Placeholder(
        title: title,
        primary: primary,
        secondary: secondary,
        surface: surface,
        onSurface: onSurface,
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.title,
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.onSurface,
  });

  final String title;
  final Color primary;
  final Color secondary;
  final Color surface;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    final String initial = title.isNotEmpty
        ? title.characters.first.toUpperCase()
        : '?';
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            primary.withValues(alpha: 0.35),
            secondary.withValues(alpha: 0.20),
            surface,
          ],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w800,
            color: onSurface.withValues(alpha: 0.85),
            letterSpacing: -1,
          ),
        ),
      ),
    );
  }
}
