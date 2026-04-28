import 'package:awatv_mobile/src/features/home/home_row_item.dart';
import 'package:awatv_mobile/src/tv/d_pad.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// One horizontal Netflix-style row.
///
/// Lays out a section header (title + optional CTA) above a horizontally
/// scrolling list of poster cards. Skips rendering when [items] is empty
/// — empty rows look broken on a home surface, so we hide them rather
/// than show "no items" copy.
class HomeRow extends StatelessWidget {
  const HomeRow({
    required this.title,
    required this.items,
    this.subtitle,
    this.seeAllRoute,
    this.posterHeight,
    this.proBadge = false,
    this.focusable = false,
    this.autofocusFirst = false,
    super.key,
  });

  /// Section heading.
  final String title;

  /// Optional subtitle / hint shown next to the title.
  final String? subtitle;

  /// Items to render as poster cards.
  final List<HomeRowItem> items;

  /// Navigation target for "Hepsini gor". When null the CTA hides.
  final String? seeAllRoute;

  /// Override the default poster height. The card width follows the
  /// 2:3 poster aspect.
  final double? posterHeight;

  /// Renders a small "PRO" pill next to the title — used by the
  /// Editor's Picks row.
  final bool proBadge;

  /// When true each card is wrapped in a [FocusableTile] so the row is
  /// usable on TV / desktop. The mobile build keeps this off — Material
  /// handles focus rings adequately for touch.
  final bool focusable;

  /// When [focusable] is true, requests autofocus on the first card.
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final height = posterHeight ?? 180;
    // Card width follows the 2:3 poster aspect — narrower than the height.
    final width = height * DesignTokens.posterAspect;

    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spaceL,
              0,
              DesignTokens.spaceL,
              DesignTokens.spaceM,
            ),
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (proBadge) ...<Widget>[
                  const SizedBox(width: DesignTokens.spaceS),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      gradient: BrandColors.brandGradient,
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusS),
                    ),
                    child: const Text(
                      'PRO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (seeAllRoute != null)
                  TextButton(
                    onPressed: () => context.push(seeAllRoute!),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          scheme.onSurface.withValues(alpha: 0.85),
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spaceS,
                      ),
                    ),
                    child: const Text('Hepsini gor'),
                  ),
                if (subtitle != null && seeAllRoute == null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            // Card height plus the title strip below the artwork.
            height: height + 56,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceL,
              ),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemCount: items.length,
              separatorBuilder: (BuildContext _, int __) =>
                  const SizedBox(width: DesignTokens.spaceM),
              itemBuilder: (BuildContext context, int i) {
                final item = items[i];
                return SizedBox(
                  width: width,
                  child: _HomeRowCard(
                    item: item,
                    height: height,
                    focusable: focusable,
                    autofocus: focusable && autofocusFirst && i == 0,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeRowCard extends StatelessWidget {
  const _HomeRowCard({
    required this.item,
    required this.height,
    required this.focusable,
    required this.autofocus,
  });

  final HomeRowItem item;
  final double height;
  final bool focusable;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final card = SizedBox(
      height: height,
      child: PosterCard(
        title: item.title,
        posterUrl: item.posterUrl,
        year: item.year,
        rating: item.rating,
        showCaption: false,
        onTap: focusable ? null : () => context.push(item.detailRoute),
      ),
    );

    final progress = item.progress;
    final stack = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Stack(
          children: <Widget>[
            card,
            if (progress != null && progress > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(DesignTokens.radiusL),
                    bottomRight: Radius.circular(DesignTokens.radiusL),
                  ),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: Colors.black.withValues(alpha: 0.55),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(BrandColors.error),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: DesignTokens.spaceS),
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        if (item.plot != null && item.plot!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              item.plot!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
          )
        else if (item.year != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              item.year!.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
          ),
      ],
    );

    if (!focusable) {
      return stack;
    }
    return FocusableTile(
      autofocus: autofocus,
      semanticLabel: item.title,
      onTap: () => context.push(item.detailRoute),
      child: stack,
    );
  }
}

/// 5-card shimmer placeholder rendered while the row's data is loading.
class HomeRowSkeleton extends StatelessWidget {
  const HomeRowSkeleton({this.posterHeight, super.key});

  final double? posterHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = posterHeight ?? 180;
    final width = height * DesignTokens.posterAspect;

    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spaceL,
              0,
              DesignTokens.spaceL,
              DesignTokens.spaceM,
            ),
            child: ShimmerSkeleton.text(
              width: 160,
              height: theme.textTheme.titleLarge?.fontSize ?? 22,
            ),
          ),
          SizedBox(
            height: height + 56,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceL,
              ),
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 5,
              separatorBuilder: (BuildContext _, int __) =>
                  const SizedBox(width: DesignTokens.spaceM),
              itemBuilder: (BuildContext _, int __) {
                return SizedBox(
                  width: width,
                  height: height,
                  child: ShimmerSkeleton.poster(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
