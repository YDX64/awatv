import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme_mode_provider.dart';

/// Settings landing — theme, parental control gate, links to playlists,
/// premium and an "About" line.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceS),
        children: [
          _SectionHeader('Gorunum'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Tema'),
            subtitle: Text(_label(mode)),
            onTap: () =>
                ref.read(appThemeModeProvider.notifier).toggle(),
          ),
          const Divider(),
          _SectionHeader('Icerik'),
          ListTile(
            leading: const Icon(Icons.queue_music_outlined),
            title: const Text('Listelerim'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/playlists'),
          ),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: const Text('Dil'),
            subtitle: const Text('Turkce'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Dil secimi Phase 2 te eklenecek.',
                  ),
                ),
              );
            },
          ),
          const Divider(),
          _SectionHeader('Aile'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Aile koruma'),
            subtitle: const Text('PIN ile yetiskin icerigi gizle'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Aile koruma Premium ile birlikte aktiflesir.',
                  ),
                ),
              );
            },
          ),
          const Divider(),
          _SectionHeader('Hesap'),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('Premium'),
            subtitle: const Text('Reklamsiz, sinirsiz, kosulsuz.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/premium'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Hakkinda'),
            subtitle: const Text('AWAtv 0.1.0  -  bu makinede gelistirildi'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'AWAtv',
                applicationVersion: '0.1.0',
                applicationIcon: const Icon(Icons.live_tv_rounded, size: 32),
                children: const [
                  Text(
                    'Cross-platform IPTV oynatici. M3U / Xtream destekli, '
                    'TMDB metadata zenginlestirmeli, premium abonelikli.',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _label(ThemeMode m) => switch (m) {
        ThemeMode.system => 'Sistem',
        ThemeMode.dark => 'Koyu',
        ThemeMode.light => 'Acik',
      };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceM,
        DesignTokens.spaceM,
        DesignTokens.spaceXs,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
      ),
    );
  }
}
