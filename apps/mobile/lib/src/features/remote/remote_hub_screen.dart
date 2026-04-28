import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Two-button hub at `/remote` — the user picks which side of the
/// pairing they want this device to play.
///
/// When [Env.hasSupabase] is false we keep the route reachable but
/// surface a friendly explanation instead of the buttons; the same
/// pattern the auth feature uses so users with un-configured builds
/// never wonder why a button does nothing.
class RemoteHubScreen extends ConsumerWidget {
  const RemoteHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasBackend = Env.hasSupabase;

    return Scaffold(
      appBar: AppBar(title: const Text('Uzaktan kumanda')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceL),
          child: hasBackend
              ? _HubBody(theme: theme)
              : const _UnavailableBody(),
        ),
      ),
    );
  }
}

class _HubBody extends StatelessWidget {
  const _HubBody({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: DesignTokens.spaceM),
        Text(
          'Telefonunu uzaktan kumanda yap',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: DesignTokens.spaceS),
        Text(
          'Bir cihazi yayin ekrani, digerini kumanda olarak kullanin. '
          'Iki cihaz da AWAtv hesabinizla baglanmis olmali.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: DesignTokens.spaceXl),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext _, BoxConstraints constraints) {
              final wide = constraints.maxWidth > 720;
              final children = <Widget>[
                Expanded(
                  child: _BigChoice(
                    icon: Icons.tv_rounded,
                    title: 'Bu cihaz ekran olsun',
                    subtitle:
                        'QR ve 6 hane gosterilir. Telefonunuz tarayarak baglanir.',
                    onTap: () => context.push('/remote/receive'),
                  ),
                ),
                if (wide)
                  const SizedBox(width: DesignTokens.spaceL)
                else
                  const SizedBox(height: DesignTokens.spaceL),
                Expanded(
                  child: _BigChoice(
                    icon: Icons.settings_remote_rounded,
                    title: 'Bu cihaz kumanda olsun',
                    subtitle:
                        'Ekranda gorulen 6 haneli kodu girerek baglanin.',
                    onTap: () => context.push('/remote/send'),
                  ),
                ),
              ];
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    );
            },
          ),
        ),
      ],
    );
  }
}

class _BigChoice extends StatelessWidget {
  const _BigChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: DesignTokens.spaceL),
              Text(
                title,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: DesignTokens.spaceS),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnavailableBody extends StatelessWidget {
  const _UnavailableBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Bulut hesabi gerekli',
        subtitle:
            'Uzaktan kumanda icin AWAtv hesabi ile giris yapmaniz gerekir. '
            'Bu yapida Supabase yapilandirmasi yok.',
      ),
    );
  }
}
