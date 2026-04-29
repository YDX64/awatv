import 'package:awatv_mobile/src/app/theme_mode_provider.dart';
import 'package:awatv_mobile/src/features/premium/premium_badge.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/auth/cloud_sync_gate.dart';
import 'package:awatv_mobile/src/shared/discovery/share_helper.dart';
import 'package:awatv_mobile/src/shared/network/app_settings_helper.dart';
import 'package:awatv_mobile/src/shared/observability/observability_provider.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/sync/cloud_sync_providers.dart';
import 'package:awatv_mobile/src/shared/sync/sync_status.dart';
import 'package:awatv_mobile/src/shared/updater/update_settings_card.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
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
      appBar: AppBar(title: Text('tabs.settings'.tr())),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceS),
        children: [
          const _SectionHeader('Hesap'),
          _AccountRow(auth: auth),
          ListTile(
            leading: const Icon(Icons.people_alt_outlined),
            title: const Text('Profiller'),
            subtitle: const Text(
              'Aileniz için ayrı kullanıcı profilleri oluşturun',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profiles'),
          ),
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
            subtitle: 'Vurgu rengini, varyantini ve kose yumusakligini sec',
            unlocked: canThemes,
            feature: PremiumFeature.customThemes,
            onUnlockedTap: () => context.push('/settings/theme'),
          ),
          // Watch-time stats — additive entry. Free users still see
          // the headline + last 7 days; premium unlocks tum-zaman.
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Izleme istatistiklerim'),
            subtitle:
                const Text('Haftalik ozet, en cok izlenenler, streak'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/stats'),
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
            title: Text('settings.language'.tr()),
            subtitle: Text(_localeLabel(context)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguagePicker(context),
          ),
          // Cloud sync is the one feature gated by BOTH premium AND
          // auth — handled inline because the lock sheet should bounce
          // premium-but-signed-out users to /login instead of /premium.
          _CloudSyncRow(
            unlocked: canCloud,
            isSignedIn: auth is AuthSignedIn,
          ),
          if (canCloud) const _SyncNowTile(),
          if (canCloud)
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: const Text('Cihazlarım'),
              subtitle: const Text(
                'Hesabınla oturum açan diğer cihazları yönet',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/devices'),
            ),
          // Remote control — pairs the device with another running
          // AWAtv install (TV, desktop). Visible to everyone; the hub
          // screen surfaces its own "needs cloud" empty state when the
          // build was compiled without Supabase.
          ListTile(
            leading: const Icon(Icons.settings_remote_outlined),
            title: const Text('Uzaktan kumanda'),
            subtitle: const Text(
              'Telefonu kumanda olarak kullan veya bu cihazi yayin ekrani yap',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/remote'),
          ),
          const Divider(),
          const _SectionHeader('Aile'),
          _GatedTile(
            icon: Icons.lock_outline,
            title: 'Aile koruma',
            subtitle: 'PIN ile yetiskin icerigi gizle',
            unlocked: canParental,
            feature: PremiumFeature.parentalControls,
            onUnlockedTap: () => context.push('/settings/parental'),
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
          const Divider(),
          // Sistem ayarlari — deep links into the OS settings screens.
          // Hidden entirely on web (no equivalent surface).
          if (!kIsWeb) ...<Widget>[
            const _SectionHeader('Sistem ayarlari'),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Bildirimler'),
              subtitle: const Text(
                'Sistem bildirim ayarlarini ac',
              ),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => openOsSettingsOrToast(
                context,
                kind: OsSettingsPage.notifications,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.wifi_outlined),
              title: const Text('Wi-Fi'),
              subtitle: const Text('Ag tercihlerini ac'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => openOsSettingsOrToast(
                context,
                kind: OsSettingsPage.wifi,
              ),
            ),
            // Pil ayarlari sadece Android'de anlamli — iOS uygulama icin
            // pil tercih sayfasi sunmaz.
            if (defaultTargetPlatform == TargetPlatform.android)
              ListTile(
                leading: const Icon(Icons.battery_5_bar_outlined),
                title: const Text('Pil'),
                subtitle: const Text(
                  'Arka plan kisitlamasini bul',
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => openOsSettingsOrToast(
                  context,
                  kind: OsSettingsPage.battery,
                ),
              ),
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Uygulama ayarlari'),
              subtitle: const Text('AWAtv izinlerini gor'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => openOsSettingsOrToast(
                context,
                kind: OsSettingsPage.app,
              ),
            ),
          ],
          const Divider(),
          const _SectionHeader('Yayilma'),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text("AWAtv'i paylas"),
            subtitle: const Text(
              'Arkadaslarini davet et, link kopyala',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ShareHelper.shareApp(context),
          ),
          const Divider(),
          const _SectionHeader('Gizlilik'),
          const _PrivacySection(),
          const Divider(),
          const _SectionHeader('Sürüm'),
          // Live version line + auto-update controls (desktop only).
          // Mobile / web see only the version row.
          const UpdateSettingsCard(),
        ],
      ),
    );
  }

  static String _label(ThemeMode m) => switch (m) {
        ThemeMode.system => 'Sistem',
        ThemeMode.dark => 'Koyu',
        ThemeMode.light => 'Acik',
      };

  /// Translates the active locale into a human-readable label. Lives
  /// here (rather than in a shared util) because language-picking is
  /// only surfaced from this one tile today; if a second consumer
  /// shows up we'll lift it.
  static String _localeLabel(BuildContext context) {
    final code = context.locale.languageCode;
    return switch (code) {
      'tr' => 'settings.language_turkish'.tr(),
      'en' => 'settings.language_english'.tr(),
      _ => code.toUpperCase(),
    };
  }

  /// Bottom sheet picker. Lists every locale exposed by easy_localization
  /// (`context.supportedLocales`) so that adding a new JSON dictionary
  /// auto-extends the picker without further wiring.
  Future<void> _showLanguagePicker(BuildContext context) async {
    final current = context.locale.languageCode;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spaceL,
                  DesignTokens.spaceS,
                  DesignTokens.spaceL,
                  DesignTokens.spaceS,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'settings.language_choose_title'.tr(),
                    style: Theme.of(sheetCtx).textTheme.titleMedium,
                  ),
                ),
              ),
              ...context.supportedLocales.map((Locale locale) {
                final code = locale.languageCode;
                final label = switch (code) {
                  'tr' => 'settings.language_turkish'.tr(),
                  'en' => 'settings.language_english'.tr(),
                  _ => code.toUpperCase(),
                };
                final selected = code == current;
                return ListTile(
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected
                        ? Theme.of(sheetCtx).colorScheme.primary
                        : null,
                  ),
                  title: Text(label),
                  selected: selected,
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    await context.setLocale(locale);
                  },
                );
              }),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spaceL,
                  DesignTokens.spaceS,
                  DesignTokens.spaceL,
                  DesignTokens.spaceL,
                ),
                child: Text(
                  'settings.language_apply_hint'.tr(),
                  style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(sheetCtx)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
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
///
/// When unlocked, the subtitle reflects the live engine status — pulled,
/// pushing, idle (with a relative timestamp), offline, or failing — so
/// the user can tell at a glance whether their last favourite tap made
/// it to the cloud.
class _CloudSyncRow extends ConsumerWidget {
  const _CloudSyncRow({
    required this.unlocked,
    required this.isSignedIn,
  });

  final bool unlocked;
  final bool isSignedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String subtitle;
    Widget trailing;
    VoidCallback onTap;

    if (unlocked) {
      // Live engine status: "Senkron — son güncelleme: 2 dakika önce",
      // "Senkron — yükleniyor…", "Bağlanılamıyor", etc.
      final statusAsync = ref.watch(cloudSyncStatusProvider);
      subtitle = statusAsync.when(
        data: (SyncStatus s) => s.localized(),
        loading: () => 'Senkron başlatılıyor…',
        error: (Object err, StackTrace _) =>
            'Senkron hatası: $err',
      );
      final isOk = statusAsync.value?.isActive ?? false;
      trailing = Icon(
        isOk ? Icons.cloud_done_rounded : Icons.cloud_outlined,
        color: isOk ? Theme.of(context).colorScheme.primary : null,
      );
      // Tap routes to the manage-devices screen so the user has somewhere
      // useful to land instead of a snackbar.
      onTap = () => context.push('/settings/devices');
    } else if (!isSignedIn) {
      subtitle = 'Senkron askıda — premium ve oturum açık olmalı';
      trailing = const Padding(
        padding: EdgeInsets.only(right: 4),
        child: PremiumBadge(),
      );
      onTap = () => context.push('/login');
    } else {
      subtitle = 'Premium ile cihazlar arası eşitleme';
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

/// "Şimdi senkronize et" tile — surfaces a manual button that runs a
/// pull → drain → push round-trip and reports the outcome inline. Visible
/// only while the engine is unlocked (premium + signed in).
///
/// Tap behaviour:
///   * idle           → calls `engine.syncNow()`, button shows spinner
///   * already running → tap is a no-op (engine.syncNow is idempotent)
///   * after success   → snackbar "Senkronizasyon tamamlandı"
///   * after failure   → snackbar with the engine's error message
class _SyncNowTile extends ConsumerStatefulWidget {
  const _SyncNowTile();

  @override
  ConsumerState<_SyncNowTile> createState() => _SyncNowTileState();
}

class _SyncNowTileState extends ConsumerState<_SyncNowTile> {
  bool _running = false;

  Future<void> _trigger() async {
    if (_running) return;
    setState(() => _running = true);
    final engine = ref.read(cloudSyncEnginePulseProvider);
    try {
      await engine.syncNow();
      if (!mounted) return;
      final status = engine.status;
      if (status is SyncFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Senkron hatası: ${status.message}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Senkronizasyon tamamlandı')),
        );
      }
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Senkron hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // We watch the status stream to drive rebuilds, but read the
    // engine's `lastSyncAt` getter directly so the timestamp survives
    // transient SyncPushing / SyncPulling phases — the engine keeps
    // the last successful round-trip cached even mid-flight.
    ref.watch(cloudSyncStatusProvider);
    final engine = ref.read(cloudSyncEnginePulseProvider);
    final lastAt = engine.lastSyncAt;
    final subtitle = lastAt == null
        ? 'Senkronizasyon henüz çalışmadı'
        : 'Son senkron: ${_formatRelativeTr(lastAt)}';
    return ListTile(
      leading: const Icon(Icons.sync_outlined),
      title: const Text('Şimdi senkronize et'),
      subtitle: Text(subtitle),
      trailing: _running
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded),
      onTap: _running ? null : _trigger,
    );
  }
}

/// Compact Turkish "X dakika önce" formatter, kept local to settings so
/// it doesn't have to be exported from sync_status.dart (where the
/// equivalent helper lives but is private).
String _formatRelativeTr(DateTime when) {
  final delta = DateTime.now().toUtc().difference(when.toUtc());
  if (delta.inSeconds < 30) return 'az önce';
  if (delta.inMinutes < 1) return '${delta.inSeconds} sn önce';
  if (delta.inMinutes == 1) return '1 dakika önce';
  if (delta.inMinutes < 60) return '${delta.inMinutes} dakika önce';
  if (delta.inHours == 1) return '1 saat önce';
  if (delta.inHours < 24) return '${delta.inHours} saat önce';
  if (delta.inDays == 1) return 'dün';
  return '${delta.inDays} gün önce';
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

/// Privacy / observability opt-in section.
///
/// Two switches:
///   * **Anonim hata bildirimi** — Crashlytics
///   * **Anonim kullanim istatistikleri** — Analytics
///
/// Both are wired to the same Hive-backed flag (`observability.optIn`)
/// because in practice users either accept *both* anonymous reporting
/// channels or none — splitting the two led to an awkward "what do
/// these even do" UX in playtests. We keep two rows so the disclosure
/// stays explicit, but flip them together.
///
/// Caveat surfaced inline: Crashlytics' collection toggle is sticky
/// for the lifetime of the process, so a freshly-disabled session can
/// still send a crash. The hint text mentions a restart so users
/// aren't surprised.
class _PrivacySection extends ConsumerWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optIn = ref.watch(observabilityOptInProvider);
    final theme = Theme.of(context);

    return Column(
      children: <Widget>[
        SwitchListTile(
          secondary: const Icon(Icons.bug_report_outlined),
          title: const Text('Anonim hata bildirimi'),
          subtitle: const Text(
            'Coken islemler hakkinda anonim bilgi gonderir, '
            'gelecekte hatalari onlemize yardimci olur.',
          ),
          value: optIn,
          onChanged: (bool v) =>
              _setOptIn(ref, context, v, restartHint: true),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.insights_outlined),
          title: const Text('Anonim kullanim istatistikleri'),
          subtitle: const Text(
            'Hangi ekranlarin daha sik kullanildigini ogrenmemize yardim et. '
            'Kisisel bilgi toplanmaz.',
          ),
          value: optIn,
          onChanged: (bool v) => _setOptIn(ref, context, v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spaceM,
            0,
            DesignTokens.spaceM,
            DesignTokens.spaceS,
          ),
          child: Text(
            'Degisiklik bir sonraki uygulama acilisinda tam olarak gecerli olur. '
            'Crashlytics gizlilik gereklilikleri nedeniyle calismakta olan '
            'oturum icin geri alinamaz.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _setOptIn(
    WidgetRef ref,
    BuildContext context,
    bool next, {
    bool restartHint = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(observabilityOptInProvider.notifier).setOptIn(next);
    final label = next
        ? 'Anonim raporlama acildi. Tesekkurler!'
        : 'Anonim raporlama kapatildi.';
    final hint = restartHint && !next
        ? ' Uygulamayi yeniden baslattiginda tam olarak devre disi kalir.'
        : '';
    messenger.showSnackBar(SnackBar(content: Text('$label$hint')));
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
