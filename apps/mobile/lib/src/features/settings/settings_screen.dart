import 'package:awatv_mobile/src/app/theme_mode_provider.dart';
import 'package:awatv_mobile/src/features/premium/premium_badge.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/auth/cloud_sync_gate.dart';
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
    // Cloud sync requires BOTH premium AND signed-in. The dedicated
    // gate provider keeps the auth-coupling in one place — when only
    // premium is true, the row still shows "sign in to enable".
    final canCloud = ref.watch(canUseCloudSyncProvider);
    final canThemes =
        ref.watch(canUseFeatureProvider(PremiumFeature.customThemes));
    final auth = ref.watch(authControllerProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceS),
        children: [
          const _SectionHeader('Hesap'),
          _AccountRow(auth: auth),
          const Divider(),
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
          // Cloud sync is the one feature gated by BOTH premium AND
          // auth — handled inline because the lock sheet should bounce
          // premium-but-signed-out users to /login instead of /premium.
          _CloudSyncRow(
            unlocked: canCloud,
            isSignedIn: auth is AuthSignedIn,
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
          const _SectionHeader('Abonelik'),
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

/// Single-row entry for the auth state at the top of settings.
///
/// Three modes:
///   - signed-in: name + email, taps to /account
///   - guest:     "Not signed in", taps to /login
///   - loading:   skeleton placeholder while the controller boots
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.auth});

  final AuthState? auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (auth is AuthSignedIn) {
      final signedIn = auth! as AuthSignedIn;
      final name = signedIn.displayName ?? signedIn.email.split('@').first;
      return ListTile(
        leading: _MiniAvatar(initials: _initialsOf(name)),
        title: Text(name),
        subtitle: Text(signedIn.email),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/account'),
      );
    }

    if (auth == null || auth is AuthLoading) {
      return ListTile(
        leading: const CircleAvatar(
          radius: 20,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        title: Text(
          'Yukleniyor…',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    // AuthGuest or AuthError — both bounce to /login. Errors are
    // rendered inline by the login screen if present.
    return ListTile(
      leading: const Icon(Icons.account_circle_outlined),
      title: const Text('Giris yap'),
      subtitle: const Text(
        'Bulut senkronizasyonu icin opsiyonel hesap aciniz',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/login'),
    );
  }

  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Cloud sync row — distinct from `_GatedTile` because the locked
/// state has two distinct fixes (sign in vs upgrade) and we want to
/// route the user to the closer one first.
class _CloudSyncRow extends StatelessWidget {
  const _CloudSyncRow({
    required this.unlocked,
    required this.isSignedIn,
  });

  final bool unlocked;
  final bool isSignedIn;

  @override
  Widget build(BuildContext context) {
    String subtitle;
    Widget trailing;
    VoidCallback onTap;

    if (unlocked) {
      subtitle = 'Favori, gecmis ve ayarlari cihazlar arasinda esitle';
      trailing = const Icon(Icons.chevron_right);
      onTap = () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bulut senkronizasyonu Phase 3 te aktiflesir.',
            ),
          ),
        );
      };
    } else if (!isSignedIn) {
      subtitle = 'Hesap aciniz, sonra premium ile aktiflesir';
      trailing = const Padding(
        padding: EdgeInsets.only(right: 4),
        child: PremiumBadge(),
      );
      onTap = () => context.push('/login');
    } else {
      subtitle = 'Premium ile cihazlar arasi esitleme';
      trailing = const Padding(
        padding: EdgeInsets.only(right: 4),
        child: PremiumBadge(),
      );
      onTap = () =>
          PremiumLockSheet.show(context, PremiumFeature.cloudSync);
    }

    return ListTile(
      leading: const Icon(Icons.cloud_sync_outlined),
      title: const Text('Bulut senkronizasyonu'),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: BrandColors.brandGradient,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
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
