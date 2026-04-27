import 'dart:ui';

import 'package:awatv_ui/src/theme/brand_colors.dart';
import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// A premium pricing tier card for the paywall.
///
/// Glassmorphism background, optional accent border for the "most popular"
/// tier, brand-gradient title, feature bullet list and a primary CTA.
/// Top-right corner carries a "BEST VALUE" / "MOST POPULAR" / "SAVE 25%"
/// ribbon when [badge] is supplied.
///
/// When [highlighted] is true the card picks up a subtle aurora glow and
/// a thicker brand-cyan border — use for whichever tier you want the user
/// to convert on.
class PriceCard extends StatelessWidget {
  const PriceCard({
    required this.title,
    required this.price,
    required this.period,
    required this.features,
    required this.onSelect,
    this.badge,
    this.highlighted = false,
    this.ctaLabel = 'Subscribe',
    this.tagline,
    super.key,
  });

  /// Tier name (e.g. "Premium").
  final String title;

  /// Price string — caller controls localisation / currency formatting.
  final String price;

  /// Billing period label (e.g. "/month", "/yr", "one-time").
  final String period;

  /// Feature bullets, rendered with check icons.
  final List<String> features;

  /// CTA tap callback. When null the button renders disabled.
  final VoidCallback? onSelect;

  /// Optional "MOST POPULAR" / "SAVE 25%" ribbon copy.
  final String? badge;

  /// Whether this is the "hero" tier — accent border + aurora glow.
  final bool highlighted;

  /// CTA button label.
  final String ctaLabel;

  /// Optional one-line tagline shown under the title (e.g. "All access").
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    final glassBase = isDark
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.85);
    final borderColor = highlighted
        ? scheme.secondary.withValues(alpha: 0.85)
        : scheme.outline.withValues(alpha: 0.45);

    final card = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: DesignTokens.blurMid,
              sigmaY: DesignTokens.blurMid,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spaceL,
                DesignTokens.spaceL,
                DesignTokens.spaceL,
                DesignTokens.spaceL,
              ),
              decoration: BoxDecoration(
                color: glassBase,
                borderRadius:
                    BorderRadius.circular(DesignTokens.radiusXL),
                border: Border.all(
                  color: borderColor,
                  width: highlighted ? 1.6 : 0.8,
                ),
                boxShadow: highlighted
                    ? <BoxShadow>[
                        BoxShadow(
                          color:
                              scheme.secondary.withValues(alpha: 0.22),
                          blurRadius: 36,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color:
                              scheme.primary.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : <BoxShadow>[
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: 0.16),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _GradientTitle(
                    title: title,
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (tagline != null && tagline!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      tagline!,
                      style: text.bodySmall?.copyWith(
                        color:
                            scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                  const SizedBox(height: DesignTokens.spaceM),
                  _PriceLine(
                    price: price,
                    period: period,
                    text: text,
                    scheme: scheme,
                  ),
                  const SizedBox(height: DesignTokens.spaceM),
                  Divider(
                    color: scheme.outline.withValues(alpha: 0.3),
                    height: 1,
                  ),
                  const SizedBox(height: DesignTokens.spaceM),
                  for (final String f in features)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: DesignTokens.spaceS,
                      ),
                      child: _FeatureBullet(
                        label: f,
                        accent: highlighted
                            ? scheme.secondary
                            : scheme.primary,
                      ),
                    ),
                  const SizedBox(height: DesignTokens.spaceS),
                  SizedBox(
                    width: double.infinity,
                    child: highlighted
                        ? _GradientCta(
                            label: ctaLabel,
                            onSelect: onSelect,
                          )
                        : FilledButton.tonal(
                            onPressed: onSelect,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                DesignTokens.minTapTarget,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  DesignTokens.radiusM,
                                ),
                              ),
                            ),
                            child: Text(ctaLabel),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (badge != null && badge!.isNotEmpty)
          Positioned(
            top: -10,
            right: DesignTokens.spaceM,
            child: _Badge(label: badge!),
          ),
      ],
    );

    return Semantics(
      label: '$title plan, $price $period',
      button: onSelect != null,
      child: card,
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.price,
    required this.period,
    required this.text,
    required this.scheme,
  });

  final String price;
  final String period;
  final TextTheme text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Flexible(
          child: Text(
            price,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -0.8,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            period,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.65),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 0.6,
            ),
          ),
          child: Icon(
            Icons.check_rounded,
            size: 14,
            color: accent,
          ),
        ),
        const SizedBox(width: DesignTokens.spaceS),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface
                  .withValues(alpha: 0.92),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _GradientTitle extends StatelessWidget {
  const _GradientTitle({required this.title, required this.style});
  final String title;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) =>
          BrandColors.brandGradient.createShader(bounds),
      child: Text(
        title,
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}

class _GradientCta extends StatelessWidget {
  const _GradientCta({required this.label, required this.onSelect});
  final String label;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onSelect != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: DesignTokens.minTapTarget,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: BrandColors.brandGradient,
                borderRadius:
                    BorderRadius.circular(DesignTokens.radiusM),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        gradient: BrandColors.premiumGradient,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFF6CD3).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}
