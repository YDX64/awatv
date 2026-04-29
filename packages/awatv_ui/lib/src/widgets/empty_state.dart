import 'package:awatv_ui/src/theme/brand_colors.dart';
import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// Friendly empty-state placeholder.
///
/// Use whenever a feature has zero content yet — favourites, search
/// results, history. The illustration is built from the supplied [icon]
/// inside a soft brand-tinted halo so we don't have to ship raster art.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.message,
    this.action,
    this.actionLabel,
    this.onAction,
    this.padding,
    super.key,
  });

  /// Glyph to anchor the illustration. Pick something distinctive for
  /// the feature (e.g. `Icons.tv_rounded` for empty channel list).
  final IconData icon;

  /// Main heading.
  final String title;

  /// Supporting copy (one or two short sentences). Prefer [message]; this
  /// is kept for backward compatibility with earlier call sites.
  final String? subtitle;

  /// Supporting copy. Wins over [subtitle] when both are provided.
  final String? message;

  /// Optional pre-built CTA widget. Wins over [actionLabel]/[onAction]
  /// when both are provided.
  final Widget? action;

  /// Convenience alternative to [action]: rendered as a `FilledButton`.
  final String? actionLabel;

  /// Callback paired with [actionLabel].
  final VoidCallback? onAction;

  /// Override the default surrounding padding.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final body = message ?? subtitle;

    // Pre-built CTA wins over the shorthand. When neither is set we
    // render no CTA at all.
    final cta = action ??
        (actionLabel != null && onAction != null
            ? FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              )
            : null);

    return Semantics(
      // The whole empty-state surface reads as one logical group so
      // screen readers announce title + body + CTA together rather
      // than fragmenting into "Boş; Henüz içerik yok; Listeye git".
      container: true,
      // headline label gives the screen-reader user the headline first;
      // children render in order beneath.
      label: title,
      hint: body,
      child: Padding(
        padding: padding ??
            const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceXl,
              vertical: DesignTokens.spaceXxl,
            ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // The illustration glyph is decorative only — exclude it
            // from the semantic tree so VoiceOver / TalkBack don't
            // announce "image" before the title.
            ExcludeSemantics(
              child: _Halo(
                icon: icon,
                primary: scheme.primary,
                secondary: scheme.secondary,
                onSurface: scheme.onSurface,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceL),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.headlineSmall,
            ),
            if (body != null && body.isNotEmpty) ...<Widget>[
              const SizedBox(height: DesignTokens.spaceS),
              Text(
                body,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
            if (cta != null) ...<Widget>[
              const SizedBox(height: DesignTokens.spaceL),
              cta,
            ],
          ],
        ),
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({
    required this.icon,
    required this.primary,
    required this.secondary,
    required this.onSurface,
  });
  final IconData icon;
  final Color primary;
  final Color secondary;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            primary.withValues(alpha: 0.30),
            secondary.withValues(alpha: 0.08),
            BrandColors.background.withValues(alpha: 0),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary.withValues(alpha: 0.12),
            border: Border.all(
              color: primary.withValues(alpha: 0.35),
            ),
          ),
          child: Icon(
            icon,
            size: 40,
            color: onSurface.withValues(alpha: 0.92),
          ),
        ),
      ),
    );
  }
}
