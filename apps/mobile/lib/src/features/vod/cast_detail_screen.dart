import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Lightweight stub for `/cast/:id` — full filmography lookup ships in
/// Phase 4. Today we just confirm the route resolves so taps from the
/// VOD detail cast row don't dead-end.
///
/// Renders the actor's display name (passed through `extra` or query
/// param) plus a "Yakinda" hint. The route stays reachable even with no
/// payload because the `id` path parameter is required and unique.
class CastDetailScreen extends StatelessWidget {
  const CastDetailScreen({
    required this.castId,
    this.name,
    super.key,
  });

  final int castId;

  /// Optional display name forwarded from the caller. When the user lands
  /// here through a deep link without a name, we fall back to the id.
  final String? name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final displayName =
        (name == null || name!.trim().isEmpty) ? 'Oyuncu #$castId' : name!;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
        title: Text(
          displayName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.person_outline_rounded,
                size: 56,
                color: scheme.primary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: DesignTokens.spaceM),
              Text(
                displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignTokens.spaceXs),
              Text(
                'Filmografi yakinda',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
