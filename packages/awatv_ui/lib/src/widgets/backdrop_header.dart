import 'package:awatv_ui/src/theme/brand_colors.dart';
import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:awatv_ui/src/widgets/rating_pill.dart';
import 'package:awatv_ui/src/widgets/shimmer_skeleton.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A full-bleed cinematic header used at the top of movie / series detail
/// screens.
///
/// Layout — a 16:9 backdrop fills the canvas, a vertical scrim fades the
/// bottom 60% to the surface colour for legibility, the poster overlaps
/// from the bottom-left, and the right column carries the title block,
/// metadata chips, rating pill, plot snippet and the primary CTA row
/// (Play + Watchlist).
///
/// Hero animations are opt-in: pass [posterHeroTag] / [backdropHeroTag]
/// only when you want the flight to animate.
///
/// A subtle parallax kicks in via [scrollProgress] (0..1) — the backdrop
/// scales 1.0 → 1.1 as the parent scroll progresses, lending the header
/// a sense of depth while the body content rises over it.
class BackdropHeader extends StatelessWidget {
  const BackdropHeader({
    required this.title,
    this.backdropUrl,
    this.posterUrl,
    this.year,
    this.rating,
    this.plot,
    this.genres = const <String>[],
    this.onPlay,
    this.onWatchlist,
    this.posterHeroTag,
    this.backdropHeroTag,
    this.scrollProgress = 0,
    super.key,
  });

  /// Title shown in display style on the right.
  final String title;

  /// 16:9 cinematic backdrop URL.
  final String? backdropUrl;

  /// 2:3 poster overlay URL.
  final String? posterUrl;

  /// Release year — displayed alongside the genre chips.
  final int? year;

  /// 0–10 rating — renders a [RatingPill] when provided.
  final double? rating;

  /// Short plot description, max three lines.
  final String? plot;

  /// Genre / category chips. Up to ~3 read well at this size.
  final List<String> genres;

  /// Primary "Play" CTA callback — hides the button when null.
  final VoidCallback? onPlay;

  /// "+ Watchlist" CTA callback — hides the button when null.
  final VoidCallback? onWatchlist;

  /// Hero tag for the poster overlay (optional).
  final String? posterHeroTag;

  /// Hero tag for the backdrop (optional).
  final String? backdropHeroTag;

  /// 0..1 scroll progress driving the parallax + fade. The widget is
  /// agnostic to the source — pass anything from a `ScrollController`,
  /// `SliverAppBar` extent, or a `NotificationListener`.
  final double scrollProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final progress = scrollProgress.clamp(0.0, 1.0);
    final backdropScale = 1.0 + 0.1 * progress;
    final contentOpacity = (1.0 - progress * 0.9).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Reserve enough height to comfortably stack the 16:9 backdrop and
        // expose the poster + title block on top of it.
        final backdropHeight = constraints.maxWidth / DesignTokens.backdropAspect;
        final headerHeight = backdropHeight + DesignTokens.spaceXxl;

        Widget backdrop = _Backdrop(
          imageUrl: backdropUrl,
          title: title,
          primary: scheme.primary,
          secondary: scheme.secondary,
          surface: scheme.surfaceContainerHighest,
        );
        if (backdropHeroTag != null) {
          backdrop = Hero(tag: backdropHeroTag!, child: backdrop);
        }

        Widget poster = _PosterOverlay(
          imageUrl: posterUrl,
          title: title,
          primary: scheme.primary,
          secondary: scheme.secondary,
          surface: scheme.surfaceContainerHighest,
          onSurface: scheme.onSurface,
        );
        if (posterHeroTag != null) {
          poster = Hero(tag: posterHeroTag!, child: poster);
        }

        return SizedBox(
          height: headerHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // Backdrop layer with parallax scale + scrim fading to the
              // page surface colour.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: backdropHeight,
                child: ClipRect(
                  child: AnimatedScale(
                    scale: backdropScale,
                    duration: DesignTokens.motionFast,
                    curve: DesignTokens.motionStandard,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        backdrop,
                        // Scrim — surface-coloured fade across the bottom 60%.
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const <double>[0, 0.4, 1],
                                colors: <Color>[
                                  scheme.surface.withValues(alpha: 0),
                                  scheme.surface.withValues(alpha: 0.55),
                                  scheme.surface,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Body content — poster overlay + title column. Positioned
              // so the poster sits roughly 1/3 from the bottom of the
              // backdrop.
              Positioned(
                left: DesignTokens.spaceL,
                right: DesignTokens.spaceL,
                bottom: 0,
                child: Opacity(
                  opacity: contentOpacity,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      SizedBox(
                        width: 124,
                        child: AspectRatio(
                          aspectRatio: DesignTokens.posterAspect,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusL,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  DesignTokens.radiusL,
                                ),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.45),
                                    blurRadius: 24,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: poster,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spaceM),
                      Expanded(
                        child: _MetaColumn(
                          title: title,
                          year: year,
                          rating: rating,
                          plot: plot,
                          genres: genres,
                          onPlay: onPlay,
                          onWatchlist: onWatchlist,
                          textTheme: text,
                          scheme: scheme,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.imageUrl,
    required this.title,
    required this.primary,
    required this.secondary,
    required this.surface,
  });

  final String? imageUrl;
  final String title;
  final Color primary;
  final Color secondary;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _BackdropPlaceholder(
        primary: primary,
        secondary: secondary,
        surface: surface,
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      fadeInDuration: DesignTokens.motionMedium,
      fadeOutDuration: DesignTokens.motionFast,
      placeholder: (BuildContext _, String __) =>
          ShimmerSkeleton.box(radius: 0),
      errorWidget: (BuildContext _, String __, Object ___) =>
          _BackdropPlaceholder(
        primary: primary,
        secondary: secondary,
        surface: surface,
      ),
    );
  }
}

class _BackdropPlaceholder extends StatelessWidget {
  const _BackdropPlaceholder({
    required this.primary,
    required this.secondary,
    required this.surface,
  });

  final Color primary;
  final Color secondary;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            primary.withValues(alpha: 0.45),
            secondary.withValues(alpha: 0.20),
            surface,
          ],
        ),
      ),
    );
  }
}

class _PosterOverlay extends StatelessWidget {
  const _PosterOverlay({
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
      final initial = title.isNotEmpty
          ? title.characters.first.toUpperCase()
          : '?';
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              primary.withValues(alpha: 0.4),
              secondary.withValues(alpha: 0.2),
              surface,
            ],
          ),
        ),
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      fadeInDuration: DesignTokens.motionMedium,
      placeholder: (BuildContext _, String __) =>
          ShimmerSkeleton.box(radius: 0),
      errorWidget: (BuildContext _, String __, Object ___) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              primary.withValues(alpha: 0.4),
              surface,
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaColumn extends StatelessWidget {
  const _MetaColumn({
    required this.title,
    required this.year,
    required this.rating,
    required this.plot,
    required this.genres,
    required this.onPlay,
    required this.onWatchlist,
    required this.textTheme,
    required this.scheme,
  });

  final String title;
  final int? year;
  final double? rating;
  final String? plot;
  final List<String> genres;
  final VoidCallback? onPlay;
  final VoidCallback? onWatchlist;
  final TextTheme textTheme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (year != null) _MetaChip(label: year!.toString()),
      ...genres.take(3).map((String g) => _MetaChip(label: g)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.4,
          ),
        ),
        if (chips.isNotEmpty || rating != null) ...<Widget>[
          const SizedBox(height: DesignTokens.spaceS),
          Wrap(
            spacing: DesignTokens.spaceS,
            runSpacing: DesignTokens.spaceXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ...chips,
              if (rating != null) RatingPill(rating: rating!, compact: true),
            ],
          ),
        ],
        if (plot != null && plot!.isNotEmpty) ...<Widget>[
          const SizedBox(height: DesignTokens.spaceS),
          Text(
            plot!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.78),
              height: 1.35,
            ),
          ),
        ],
        if (onPlay != null || onWatchlist != null) ...<Widget>[
          const SizedBox(height: DesignTokens.spaceM),
          Wrap(
            spacing: DesignTokens.spaceS,
            runSpacing: DesignTokens.spaceS,
            children: <Widget>[
              if (onPlay != null)
                FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
              if (onWatchlist != null)
                OutlinedButton.icon(
                  onPressed: onWatchlist,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Watchlist'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceS,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        border: Border.all(
          color: BrandColors.outlineGlass,
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
      ),
    );
  }
}
