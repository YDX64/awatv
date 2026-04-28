import 'dart:async';

import 'package:awatv_mobile/src/features/home/home_row_item.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Auto-rotating hero carousel that fronts the home screen.
///
/// - 16:9 backdrop slot. Falls back to the poster scaled-out if no
///   backdrop is available (provider catalogues are inconsistent).
/// - Up to 5 slots. Auto-advances every [autoAdvance] ticks; user
///   gestures pause the timer for one cycle to avoid stealing focus
///   while they read.
/// - Bottom CTA reflects what the user can do: "Devam et" when there's
///   resume progress, otherwise "Izle".
class HomeHero extends StatefulWidget {
  const HomeHero({
    required this.slots,
    this.autoAdvance = const Duration(seconds: 8),
    this.height,
    super.key,
  });

  final List<HomeRowItem> slots;
  final Duration autoAdvance;
  final double? height;

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  late final PageController _pc = PageController();
  Timer? _timer;
  int _index = 0;
  bool _userInteracted = false;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  @override
  void didUpdateWidget(covariant HomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the slot count drops below the current index (e.g. a continue
    // watching item finished playing) — clamp so we don't scroll into
    // empty space.
    if (_index >= widget.slots.length && widget.slots.isNotEmpty) {
      _index = 0;
      _pc.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (widget.slots.length < 2) return;
    _timer = Timer(widget.autoAdvance, _advance);
  }

  void _advance() {
    if (!mounted || widget.slots.isEmpty) return;
    if (_userInteracted) {
      // Skip one cycle then resume normal cadence.
      _userInteracted = false;
      _scheduleNext();
      return;
    }
    final next = (_index + 1) % widget.slots.length;
    _pc.animateToPage(
      next,
      duration: DesignTokens.motionMedium,
      curve: DesignTokens.motionStandard,
    );
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    _scheduleNext();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slots.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (BuildContext _, BoxConstraints c) {
        final height =
            widget.height ?? (c.maxWidth / DesignTokens.backdropAspect);
        return SizedBox(
          height: height,
          child: Listener(
            onPointerDown: (_) => _userInteracted = true,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                PageView.builder(
                  controller: _pc,
                  onPageChanged: _onPageChanged,
                  itemCount: widget.slots.length,
                  itemBuilder: (BuildContext _, int i) =>
                      _HeroSlide(item: widget.slots[i]),
                ),
                // Bottom dots — drawn over the scrim.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: DesignTokens.spaceM,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (int i = 0; i < widget.slots.length; i++)
                        AnimatedContainer(
                          duration: DesignTokens.motionFast,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _index ? 22 : 8,
                          height: 4,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? scheme.primary
                                : scheme.onSurface.withValues(alpha: 0.45),
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusS),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({required this.item});

  final HomeRowItem item;

  String? get _imageUrl =>
      (item.backdropUrl != null && item.backdropUrl!.isNotEmpty)
          ? item.backdropUrl
          : item.posterUrl;

  bool get _hasResume {
    final p = item.progress;
    return p != null && p > 0.01 && p < 0.95;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final url = _imageUrl;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (url != null && url.isNotEmpty)
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            fadeInDuration: DesignTokens.motionMedium,
            placeholder: (BuildContext _, String __) => DecoratedBox(
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
            ),
            errorWidget: (BuildContext _, String __, Object ___) =>
                _HeroFallback(title: item.title),
          )
        else
          _HeroFallback(title: item.title),
        // Bottom-up legibility scrim.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const <double>[0, 0.5, 1],
                colors: <Color>[
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.45),
                  scheme.surface,
                ],
              ),
            ),
          ),
        ),
        // Brand-tinted left scrim for the meta column.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  BrandColors.primary.withValues(alpha: 0.22),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: DesignTokens.spaceL,
          right: DesignTokens.spaceL,
          bottom: DesignTokens.spaceXxl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  shadows: const <Shadow>[
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 12,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              if (item.plot != null && item.plot!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: DesignTokens.spaceS),
                  child: Text(
                    item.plot!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      height: 1.35,
                    ),
                  ),
                ),
              const SizedBox(height: DesignTokens.spaceM),
              Row(
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () => context.push(item.detailRoute),
                    icon: Icon(
                      _hasResume
                          ? Icons.play_arrow_rounded
                          : Icons.play_circle_filled_rounded,
                    ),
                    label: Text(_hasResume ? 'Devam et' : 'Izle'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: BrandColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spaceL,
                        vertical: DesignTokens.spaceM,
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceS),
                  if (item.rating != null) RatingPill(rating: item.rating!),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = title.isNotEmpty ? title.characters.first.toUpperCase() : '';
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            BrandColors.primary.withValues(alpha: 0.4),
            BrandColors.secondary.withValues(alpha: 0.2),
            scheme.surface,
          ],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w900,
            color: Colors.white24,
          ),
        ),
      ),
    );
  }
}
