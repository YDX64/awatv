import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:awatv_ui/src/widgets/gradient_scrim.dart';
import 'package:awatv_ui/src/widgets/rating_pill.dart';
import 'package:awatv_ui/src/widgets/shimmer_skeleton.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Visual orientation for [PosterCard].
///
/// * [portrait] — 2:3 movie/series poster (default).
/// * [landscape] — ~16:9 backdrop, used for "continue watching" rails and
///   episode strips.
/// * [logo] — square channel logo card.
enum PosterCardVariant { portrait, landscape, logo }

/// Streas-tinted badge slot rendered in the top-left corner of a card.
///
/// `NEW` / `POPULAR` / `PREMIUM` are rendered with a cherry-tinted pill so
/// content rails surface freshness/quality cues without screaming for
/// attention. Use `null` to suppress the badge.
enum PosterCardBadge { none, isNew, popular, premium }

/// A poster / backdrop / channel-logo card.
///
/// Renders the artwork with a legibility scrim, an overlaid rating pill, an
/// optional cherry-tinted "NEW" / "POPULAR" / "PREMIUM" badge in the
/// top-left, and a title strip below. Includes:
///
///   * Hero animation when [heroTag] is supplied.
///   * Spring-style press scale (0.98) + opacity dip (per Streas spec) for
///     tactile feedback.
///   * Shimmer loading state and graceful gradient placeholder on error.
///
/// Three named variants (or use the [variant] argument):
///
/// ```dart
/// PosterCard.portrait(title: 'The Bear', imageUrl: …)
/// PosterCard.landscape(title: 'Continue', imageUrl: …, width: 200)
/// PosterCard.logo(title: 'BBC One', imageUrl: …, width: 96)
/// ```
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
    this.variant = PosterCardVariant.portrait,
    this.badge = PosterCardBadge.none,
    this.progress,
    super.key,
  });

  /// Portrait 2:3 poster — the default.
  ///
  /// `width` defaults to 110 to match the Streas content card.
  const PosterCard.portrait({
    required this.title,
    this.imageUrl,
    this.posterUrl,
    this.rating,
    this.year,
    this.subtitle,
    this.onTap,
    this.heroTag,
    this.width = 110,
    this.showCaption = true,
    this.badge = PosterCardBadge.none,
    this.progress,
    super.key,
  }) : variant = PosterCardVariant.portrait;

  /// Landscape ~16:9 backdrop card.
  ///
  /// `width` defaults to 200 to match the Streas continue-watching rail.
  const PosterCard.landscape({
    required this.title,
    this.imageUrl,
    this.posterUrl,
    this.rating,
    this.year,
    this.subtitle,
    this.onTap,
    this.heroTag,
    this.width = 200,
    this.showCaption = true,
    this.badge = PosterCardBadge.none,
    this.progress,
    super.key,
  }) : variant = PosterCardVariant.landscape;

  /// Square channel-logo card.
  ///
  /// Renders the artwork with a tight padding so logos look centred rather
  /// than bleeding to the edge. `width` defaults to 96.
  const PosterCard.logo({
    required this.title,
    this.imageUrl,
    this.posterUrl,
    this.onTap,
    this.heroTag,
    this.width = 96,
    this.showCaption = false,
    this.badge = PosterCardBadge.none,
    super.key,
  })  : variant = PosterCardVariant.logo,
        rating = null,
        year = null,
        subtitle = null,
        progress = null;

  /// Title label, also used as fallback initial when no image URL is set.
  final String title;

  /// Remote URL. Either [imageUrl] or [posterUrl] is acceptable; when both
  /// are null/empty the gradient placeholder is rendered.
  final String? imageUrl;

  /// Alias for [imageUrl] — accepted because most call sites store
  /// posters under a `posterUrl` field.
  final String? posterUrl;

  /// 0–10 score; renders a rating pill when supplied. Ignored on
  /// [PosterCardVariant.logo].
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

  /// Visual orientation — see [PosterCardVariant].
  final PosterCardVariant variant;

  /// Cherry-tinted badge to render in the top-left corner.
  final PosterCardBadge badge;

  /// 0..1 watch progress; renders a thin cherry strip across the bottom.
  /// Ignored on [PosterCardVariant.logo].
  final double? progress;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: DesignTokens.motionFast,
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

  String? _resolveImage() {
    final primary = widget.imageUrl;
    final secondary = widget.posterUrl;
    if (primary != null && primary.isNotEmpty) return primary;
    if (secondary != null && secondary.isNotEmpty) return secondary;
    return null;
  }

  double _aspectFor(PosterCardVariant variant) {
    switch (variant) {
      case PosterCardVariant.portrait:
        return DesignTokens.posterAspect; // 2/3
      case PosterCardVariant.landscape:
        return DesignTokens.backdropAspect; // 16/9
      case PosterCardVariant.logo:
        return 1; // square
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final image = _resolveImage();
    final aspect = _aspectFor(widget.variant);
    final isLogo = widget.variant == PosterCardVariant.logo;

    Widget artwork = AspectRatio(
      aspectRatio: aspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          isLogo ? DesignTokens.radiusM : DesignTokens.radiusL,
        ),
        child: GradientScrim(
          intensity: isLogo ? 0 : 0.85,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _PosterImage(
                imageUrl: image,
                title: widget.title,
                primary: scheme.primary,
                secondary: scheme.secondary,
                surface: scheme.surfaceContainerHighest,
                onSurface: scheme.onSurface,
                contain: isLogo,
              ),
              if (widget.badge != PosterCardBadge.none)
                Positioned(
                  top: 6,
                  left: 6,
                  child: _CherryBadge(
                    badge: widget.badge,
                    color: scheme.primary,
                  ),
                ),
              if (!isLogo && widget.rating != null)
                Positioned(
                  top: DesignTokens.spaceS,
                  right: DesignTokens.spaceS,
                  child: RatingPill(rating: widget.rating!),
                ),
              if (!isLogo &&
                  widget.progress != null &&
                  widget.progress! > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _ProgressBar(
                    value: widget.progress!.clamp(0.0, 1.0),
                    track: Colors.white.withValues(alpha: 0.2),
                    fill: scheme.primary,
                  ),
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
          // Streas press feedback: scale 0.98 + opacity dip 0.85 (close to
          // RN's `activeOpacity={0.75-0.85}`). Keep the dip soft so it
          // doesn't feel bouncy on a long press.
          final t = _press.value;
          return Transform.scale(
            scale: 1 - (0.02 * t),
            child: Opacity(
              opacity: 1 - (0.15 * t),
              child: child,
            ),
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
    this.contain = false,
  });

  final String? imageUrl;
  final String title;
  final Color primary;
  final Color secondary;
  final Color surface;
  final Color onSurface;
  final bool contain;

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
    return Container(
      color: contain ? surface : null,
      padding: contain ? const EdgeInsets.all(DesignTokens.spaceS) : null,
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: contain ? BoxFit.contain : BoxFit.cover,
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
    final initial = title.isNotEmpty
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

class _CherryBadge extends StatelessWidget {
  const _CherryBadge({required this.badge, required this.color});

  final PosterCardBadge badge;
  final Color color;

  String get _label {
    switch (badge) {
      case PosterCardBadge.isNew:
        return 'NEW';
      case PosterCardBadge.popular:
        return 'POPULAR';
      case PosterCardBadge.premium:
        return 'PREMIUM';
      case PosterCardBadge.none:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        _label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.value,
    required this.track,
    required this.fill,
  });

  final double value;
  final Color track;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: track),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: ColoredBox(color: fill),
          ),
        ],
      ),
    );
  }
}
