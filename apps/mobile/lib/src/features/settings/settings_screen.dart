import 'package:awatv_mobile/src/app/theme_mode_provider.dart';
import 'package:awatv_mobile/src/features/premium/premium_badge.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings landing — theme, parental control gate, links to playlists,
/// premium and an "About" line.
///
/// Premium-only rows ("Cloud sync", "Parental controls", "Custom
/// themes") render with a small lock icon while the user is on the
/// free tier; tapping them opens the [PremiumLockSheet] instead of
/// navigating into the (not-yet-built) feature.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    final canParental =
        ref.watch(canUseFeatureProvider(PremiumFeature.parentalControls));
    final canCloud = ref.watch(canUseFeatureProvider(PremiumFeature.cloudSync));
    final canThemes =
        ref.watch(canUseFeatureProvider(PremiumFeature.customThemes));

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceS),
        children: [
          const _SectionHeader('Gorunum'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Tema'),
            subtitle: Text(_label(mode)),
            onTap: () => ref.read(appThemeModeProvider.notifier).toggle(),
          ),
          _GatedTile(
            icon: Icons.palette_outlined,
            title: 'Ozel temalar',
            subtitle: 'Vurgu rengini ve duvar kagidini secin',
            unlocked: canThemes,
            feature: PremiumFeature.customThemes,
            onUnlockedTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ozel temalar yakinda eklenecek.'),
                ),
              );
            },
          ),
          const Divider(),
          const _SectionHeader('Icerik'),
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
                  content: Text('Dil secimi Phase 2 te eklenecek.'),
                ),
              );
            },
          ),
          _GatedTile(
            icon: Icons.cloud_sync_outlined,
            title: 'Bulut senkronizasyonu',
            subtitle: 'Favori, gecmis ve ayarlari cihazlar arasinda esitle',
            unlocked: canCloud,
            feature: PremiumFeature.cloudSync,
            onUnlockedTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Bulut senkronizasyonu Phase 3 te aktiflesir.',
                  ),
                ),
              );
            },
          ),
          const Divider(),
          const _SectionHeader('Aile'),
          _GatedTile(
            icon: Icons.lock_outline,
            title: 'Aile koruma',
            subtitle: 'PIN ile yetiskin icerigi gizle',
            unlocked: canParental,
            feature: PremiumFeature.parentalControls,
            onUnlockedTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Aile koruma kurulumu yakinda eklenecek.',
                  ),
                ),
              );
            },
          ),
          const Divider(),
          const _SectionHeader('Hesap'),
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

/// List row that swaps its trailing affordance based on whether the
/// active tier covers the linked [PremiumFeature]. Locked taps surface
/// the [PremiumLockSheet]; unlocked taps fall through to the screen's
/// own handler.
class _GatedTile extends StatelessWidget {
  const _GatedTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.unlocked,
    required this.feature,
    required this.onUnlockedTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool unlocked;
  final PremiumFeature feature;
  final VoidCallback onUnlockedTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: unlocked
          ? const Icon(Icons.chevron_right)
          : const Padding(
              padding: EdgeInsets.only(right: 4),
              child: PremiumBadge(),
            ),
      onTap: () {
        if (!unlocked) {
          PremiumLockSheet.show(context, feature);
          return;
        }
        onUnlockedTap();
      },
    );
  }
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
