import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Loading-state placeholders.
///
/// Use the named constructors below to drop in a shimmer of the correct
/// shape for the content that's about to appear. Keeping them aligned
/// with their final layout reduces layout-shift jank when the data lands.
class ShimmerSkeleton extends StatelessWidget {
  const ShimmerSkeleton._({
    required this.child,
    super.key,
  });

  /// A poster-shaped (2:3) shimmer block, ready to drop into a vertical
  /// list or grid alongside real `PosterCard` widgets.
  factory ShimmerSkeleton.poster({Key? key}) {
    return ShimmerSkeleton._(
      key: key,
      child: const _PosterPlaceholder(),
    );
  }

  /// A horizontal channel-row shimmer (logo + two stacked text bars).
  factory ShimmerSkeleton.channelTile({Key? key}) {
    return ShimmerSkeleton._(
      key: key,
      child: const _ChannelTilePlaceholder(),
    );
  }

  /// A single text bar — useful when only a title is loading.
  factory ShimmerSkeleton.text({
    Key? key,
    double width = 100,
    double height = 12,
  }) {
    return ShimmerSkeleton._(
      key: key,
      child: _TextBar(width: width, height: height),
    );
  }

  /// A free-form shimmer rectangle. Use when none of the helpers fit.
  factory ShimmerSkeleton.box({
    Key? key,
    double? width,
    double? height,
    double radius = DesignTokens.radiusM,
  }) {
    return ShimmerSkeleton._(
      key: key,
      child: _Block(width: width, height: height, radius: radius),
    );
  }

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color base = isDark
        ? scheme.surfaceContainerHighest
        : scheme.surfaceContainerHighest.withValues(alpha: 0.7);
    final Color highlight = isDark
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.06),
            scheme.surface,
          )
        : Colors.white;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AspectRatio(
          aspectRatio: DesignTokens.posterAspect,
          child: _Block(
            radius: DesignTokens.radiusL,
          ),
        ),
        SizedBox(height: DesignTokens.spaceS),
        _TextBar(width: 120, height: 12),
        SizedBox(height: DesignTokens.spaceXs),
        _TextBar(width: 60, height: 10),
      ],
    );
  }
}

class _ChannelTilePlaceholder extends StatelessWidget {
  const _ChannelTilePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: DesignTokens.spaceS,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            height: 64,
            child: _Block(radius: DesignTokens.radiusM),
          ),
          SizedBox(width: DesignTokens.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _TextBar(width: 160, height: 14),
                SizedBox(height: DesignTokens.spaceS),
                _TextBar(width: 240, height: 10),
                SizedBox(height: DesignTokens.spaceXs),
                _TextBar(width: 100, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextBar extends StatelessWidget {
  const _TextBar({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _Block(
      width: width,
      height: height,
      radius: height / 2,
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({this.width, this.height, this.radius = DesignTokens.radiusM});
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
