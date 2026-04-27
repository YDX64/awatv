import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// Compact, theme-aware loading state used inside `AsyncValue.when`.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            const SizedBox(height: DesignTokens.spaceM),
            Text(
              label!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen loading view used between routes / on cold start.
class FullPageLoading extends StatelessWidget {
  const FullPageLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: LoadingView(label: label)),
    );
  }
}
