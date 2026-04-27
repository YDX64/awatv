import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// First-run welcome — hero illustration + a single CTA that pushes
/// the add-playlist form. Once at least one source is added the
/// router redirect drops the user straight into the channels grid.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: BrandColors.brandGradient,
                  ),
                  child: const Icon(
                    Icons.live_tv_rounded,
                    size: 84,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: DesignTokens.spaceXl),
              Text(
                'AWAtv ye hosgeldin',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: DesignTokens.spaceS),
              Text(
                'Kendi M3U veya Xtream Codes oynatma listenle '
                'canli kanallari, filmleri ve dizileri tek catida toplayalim.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => context.push('/playlists/add'),
                icon: const Icon(Icons.add_link),
                label: const Text('Ilk listeni ekle'),
              ),
              const SizedBox(height: DesignTokens.spaceM),
              // Privacy reassurance — addresses the "where does my
              // data go?" question before users have to ask.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceM,
                  vertical: DesignTokens.spaceS,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusM),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: DesignTokens.spaceS),
                    Expanded(
                      child: Text(
                        'Listen bu cihazda kalir. Birden fazla cihazda '
                        'kullanmak istersen giris yapabilirsin.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.spaceS),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  TextButton(
                    onPressed: () => context.push('/login'),
                    child: const Text('Hesabin var mi? Giris yap'),
                  ),
                  Text(
                    '·',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/premium'),
                    child: const Text('Premium'),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.spaceM),
            ],
          ),
        ),
      ),
    );
  }
}
