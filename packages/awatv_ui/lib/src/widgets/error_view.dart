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
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextTheme text = theme.textTheme;
    final String resolvedTitle = title ?? 'Something went wrong';

    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceXl,
            vertical: DesignTokens.spaceXl,
          ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.error.withValues(alpha: 0.12),
              border: Border.all(
                color: scheme.error.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 36,
              color: scheme.error,
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
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}
