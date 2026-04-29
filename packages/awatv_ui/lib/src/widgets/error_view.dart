import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// A friendly error UI with optional retry action.
///
/// Designed to wrap a feature surface when its data load fails. Pairs
/// well with `AsyncValue.when(error: ...)` from Riverpod.
class ErrorView extends StatelessWidget {
  const ErrorView({
    required this.message,
    this.onRetry,
    this.title,
    this.icon = Icons.error_outline_rounded,
    this.padding,
    super.key,
  });

  /// Main error message — keep it human ("We couldn't reach the server").
  final String message;

  /// Optional title shown above [message]; defaults to "Something went
  /// wrong".
  final String? title;

  /// Glyph used in the halo. Defaults to a rounded info icon.
  final IconData icon;

  /// Retry callback. Hides the button when null.
  final VoidCallback? onRetry;

  /// Override outer padding.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final resolvedTitle = title ?? 'Something went wrong';

    return Semantics(
      // Group the error-illustration + body so VoiceOver announces it
      // as one unit. liveRegion=true ensures the error is read out the
      // moment it lands on screen — screen-reader users shouldn't have
      // to discover an error by re-scanning the page.
      container: true,
      liveRegion: true,
      label: resolvedTitle,
      hint: message,
      child: Padding(
        padding: padding ??
            const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceXl,
              vertical: DesignTokens.spaceXl,
            ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // The error halo is purely decorative — its meaning is
            // already in the title text. Exclude it so the screen
            // reader doesn't read out "image" before the title.
            ExcludeSemantics(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.error.withValues(alpha: 0.12),
                  border: Border.all(
                    color: scheme.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(
                  icon,
                  size: 36,
                  color: scheme.error,
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceL),
            Text(
              resolvedTitle,
              textAlign: TextAlign.center,
              style: text.titleLarge,
            ),
            const SizedBox(height: DesignTokens.spaceS),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: DesignTokens.spaceL),
              // FilledButton.icon already exposes Semantics; we pass
              // an explicit semanticsLabel via Tooltip so users on
              // touch devices also get a long-press hint.
              Tooltip(
                message: 'Try again',
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
