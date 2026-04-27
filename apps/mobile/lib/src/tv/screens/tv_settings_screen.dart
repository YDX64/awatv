import 'package:awatv_mobile/src/app/theme_mode_provider.dart';
import 'package:awatv_mobile/src/tv/d_pad.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 10-foot settings list. Focusable rows, large hit targets.
class TvSettingsScreen extends ConsumerWidget {
  const TvSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceXl,
        DesignTokens.spaceL,
        DesignTokens.spaceXl,
        DesignTokens.spaceL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Ayarlar',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                _SettingsRow(
                  icon: Icons.brightness_6_outlined,
                  title: 'Tema',
                  subtitle: _modeLabel(mode),
                  autofocus: true,
                  onTap: () =>
                      ref.read(appThemeModeProvider.notifier).toggle(),
                ),
                const SizedBox(height: DesignTokens.spaceM),
                _SettingsRow(
                  icon: Icons.queue_music_outlined,
                  title: 'Listelerim',
                  subtitle: 'M3U / Xtream kaynaklarini yonet',
                  onTap: () => context.push('/playlists'),
                ),
                const SizedBox(height: DesignTokens.spaceM),
                _SettingsRow(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Premium',
                  subtitle: 'Reklamsiz, sinirsiz, kosulsuz.',
                  onTap: () => context.push('/premium'),
                ),
                const SizedBox(height: DesignTokens.spaceM),
                _SettingsRow(
                  icon: Icons.lock_outline,
                  title: 'Aile koruma',
                  subtitle: 'PIN ile yetiskin icerigi gizle',
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
                const SizedBox(height: DesignTokens.spaceM),
                _SettingsRow(
                  icon: Icons.info_outline,
                  title: 'Hakkinda',
                  subtitle: 'AWAtv 0.1.0',
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'AWAtv',
                      applicationVersion: '0.1.0',
                      applicationIcon:
                          const Icon(Icons.live_tv_rounded, size: 32),
                      children: const <Widget>[
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
          ),
        ],
      ),
    );
  }

  static String _modeLabel(ThemeMode m) => switch (m) {
        ThemeMode.system => 'Sistem',
        ThemeMode.dark => 'Koyu',
        ThemeMode.light => 'Acik',
      };
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FocusableTile(
      autofocus: autofocus,
      semanticLabel: title,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceL,
          vertical: DesignTokens.spaceL,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 32, color: scheme.primary),
            const SizedBox(width: DesignTokens.spaceL),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 16,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: scheme.onSurface.withValues(alpha: 0.55),
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}
