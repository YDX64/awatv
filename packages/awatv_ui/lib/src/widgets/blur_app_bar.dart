import 'dart:ui';

import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// A glass-flavoured `SliverAppBar`.
///
/// Sits transparent on top of imagery while the user is at the top of
/// the scroll view, then fades in a frosted backdrop and the title as
/// they scroll. Pair with `CustomScrollView` and a leading hero header.
class BlurAppBar extends StatelessWidget {
  const BlurAppBar({
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.expandedContent,
    this.expandedHeight = 0,
    this.pinned = true,
    this.floating = false,
    this.centerTitle = false,
    this.blur = DesignTokens.blurMid,
    super.key,
  });

  /// Primary title — fades in with the scrim.
  final String title;

  /// Optional subtitle under the title.
  final String? subtitle;

  /// Trailing actions.
  final List<Widget>? actions;

  /// Leading widget (defaults to back arrow when navigation is possible).
  final Widget? leading;

  /// Extra content behind the bar (hero artwork, gradient, etc.).
  final Widget? expandedContent;

  /// Total expanded height — set this when [expandedContent] is provided.
  final double expandedHeight;

  /// Whether the bar stays pinned during scroll.
  final bool pinned;

  /// Whether the bar reappears as soon as the user scrolls up.
  final bool floating;

  /// Centre-align the title (off by default for a left-leaning feel).
  final bool centerTitle;

  /// Blur sigma applied to the backdrop.
  final double blur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final veil = isDark
        ? scheme.surface.withValues(alpha: 0.55)
        : scheme.surface.withValues(alpha: 0.7);

    return SliverAppBar(
      pinned: pinned,
      floating: floating,
      stretch: true,
      expandedHeight: expandedHeight > 0 ? expandedHeight : null,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: DesignTokens.spaceS,
      centerTitle: centerTitle,
      leading: leading,
      actions: actions,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: FlexibleSpaceBar(
            stretchModes: const <StretchMode>[
              StretchMode.zoomBackground,
              StretchMode.fadeTitle,
            ],
            titlePadding: const EdgeInsetsDirectional.fromSTEB(
              DesignTokens.spaceM,
              0,
              DesignTokens.spaceM,
              DesignTokens.spaceM,
            ),
            title: _CollapsedTitle(
              title: title,
              subtitle: subtitle,
              centerTitle: centerTitle,
            ),
            background: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (expandedContent != null) expandedContent!,
                // Veil — gives the title contrast against busy imagery.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          veil,
                          veil.withValues(alpha: 0),
                        ],
                        stops: const <double>[0, 0.6],
                      ),
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

class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle({
    required this.title,
    required this.subtitle,
    required this.centerTitle,
  });

  final String title;
  final String? subtitle;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      // Mark the screen title as a heading so screen-reader users can
      // jump between major sections via the heading shortcut. Subtitle
      // tags as the value/hint so it's announced after the heading.
      header: true,
      label: title,
      hint: (subtitle?.isNotEmpty ?? false) ? subtitle : null,
      child: Column(
        crossAxisAlignment:
            centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Exclude the descendants from semantics — the parent already
          // announces the title + hint.
          ExcludeSemantics(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleLarge,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            ExcludeSemantics(
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium?.copyWith(
                  color: text.bodySmall?.color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
