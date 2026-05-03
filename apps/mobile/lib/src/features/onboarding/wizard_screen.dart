import 'dart:io' show Platform, Process;

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/features/playlists/playlist_providers.dart';
import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/discovery/discovered_iptv_server.dart';
import 'package:awatv_mobile/src/shared/discovery/local_iptv_discovery.dart';
import 'package:awatv_mobile/src/shared/notifications/notifications_provider.dart';
import 'package:awatv_mobile/src/shared/observability/awatv_observability.dart';
import 'package:awatv_mobile/src/shared/observability/observability_provider.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:uuid/uuid.dart';

/// Hive prefs key tracking how far through the wizard the user has
/// progressed. Empty / "false" → still pending; "completed" → wizard
/// has been finished and the regular onboarding redirect skips it.
const String _kOnboardingDoneKey = 'prefs:onboarding.completed';

/// Seven-step onboarding wizard.
///
/// Steps:
///   1. **Welcome** — brand hero + tagline + "Devam"
///   2. **Sign in / Sign up** — Supabase auth with three modes: Sign In,
///      Sign Up, or "Misafir Devam Et". Signed-in users get automatic
///      cloud sync of playlists, favourites, and watch history through
///      `cloud_sync_engine.dart`.
///   3. **Privacy** — Crashlytics + Analytics opt-in toggles
///   4. **Notifications** — request OS notification permission
///   5. **First playlist** — M3U / Xtream / Stalker form + Bonjour
///      discovery preview (cannot skip — adding a source is the only
///      way out). Surfaces a "bulutla yedeklenecek" hint when the user
///      is signed in, so they know their list will follow them across
///      devices instead of having to be re-entered.
///   6. **Premium teaser** — high-level pitch of the 9 paid features +
///      "Detaylar" pivot to /premium. Skippable — most users explore
///      the app first and convert later.
///   7. **All set** — success animation + "Hadi baslayalim" → /home
///
/// Persists progress in Hive so a partial onboarding can be resumed
/// after a kill/restart.
class OnboardingWizardScreen extends ConsumerStatefulWidget {
  const OnboardingWizardScreen({super.key});

  @override
  ConsumerState<OnboardingWizardScreen> createState() =>
      _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState
    extends ConsumerState<OnboardingWizardScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  // Privacy step now manages its own state inside `_StepPrivacy`,
  // persisting toggles directly to Hive on every change so the
  // "set-but-forgotten" GDPR bug from earlier versions is gone.

  // Notification permission outcome.
  bool? _notificationsGranted;

  // Step 4 — playlist form values.
  PlaylistKind _kind = PlaylistKind.m3u;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _macCtrl = TextEditingController();
  final TextEditingController _epgCtrl = TextEditingController();
  bool _busyAdding = false;

  static const int _kStepCount = 7;

  @override
  void dispose() {
    _pages.dispose();
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _macCtrl.dispose();
    _epgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _ProgressBar(stepIndex: _index, total: _kStepCount),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (int i) => setState(() => _index = i),
                children: <Widget>[
                  _StepWelcome(onNext: _next),
                  _StepAuth(onNext: _next, onSkip: _next),
                  // GDPR: explicit choice required, no Skip button.
                  // Toggles persist to Hive immediately on change.
                  _StepPrivacy(onContinue: _next),
                  _StepNotifications(
                    granted: _notificationsGranted,
                    onAsk: _askForNotificationPermission,
                    onNext: _next,
                    onSkip: _next,
                  ),
                  _StepFirstPlaylist(
                    kind: _kind,
                    nameCtrl: _nameCtrl,
                    urlCtrl: _urlCtrl,
                    userCtrl: _userCtrl,
                    passCtrl: _passCtrl,
                    macCtrl: _macCtrl,
                    epgCtrl: _epgCtrl,
                    busy: _busyAdding,
                    onKindChanged: (PlaylistKind k) =>
                        setState(() => _kind = k),
                    onSubmit: _addPlaylist,
                    onPrefill: _onPrefillFromDiscovery,
                  ),
                  _StepPremium(onNext: _next, onSkip: _next),
                  _StepAllSet(onFinish: _finish),
                ],
              ),
            ),
            // Footer hint — shown for the welcome / privacy /
            // notifications steps so users know they can step back if
            // they tapped "Devam" too quickly.
            if (_index > 0 && _index < _kStepCount - 1)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceL,
                  vertical: DesignTokens.spaceXs,
                ),
                child: Row(
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: _previous,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: Text('onboarding.back'.tr()),
                    ),
                    const Spacer(),
                    Text(
                      '${_index + 1} / $_kStepCount',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _next() {
    if (_index >= _kStepCount - 1) return;
    _pages.animateToPage(
      _index + 1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _previous() {
    if (_index <= 0) return;
    _pages.animateToPage(
      _index - 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _askForNotificationPermission() async {
    try {
      final notif = ref.read(awatvNotificationsProvider);
      final ok = await notif.ensurePermission();
      setState(() => _notificationsGranted = ok);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _notificationsGranted = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'onboarding.permission_denied'
                .tr(namedArgs: <String, String>{'message': e.toString()}),
          ),
        ),
      );
    }
  }

  void _onPrefillFromDiscovery(DiscoveredIptvServer server) {
    setState(() {
      _kind = PlaylistKind.xtream;
      if (_nameCtrl.text.isEmpty) {
        _nameCtrl.text = server.name;
      }
      _urlCtrl.text = 'http://${server.host}:${server.port}';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${server.name} formu doldurdu — sifre + kullanici girilmeli.'),
      ),
    );
  }

  Future<void> _addPlaylist() async {
    final name = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (name.isEmpty) {
      _toast('Bir isim ver.');
      return;
    }
    if (url.isEmpty) {
      _toast('URL gerekli.');
      return;
    }
    setState(() => _busyAdding = true);
    try {
      String? username;
      String? password;
      switch (_kind) {
        case PlaylistKind.m3u:
          username = null;
          password = null;
        case PlaylistKind.xtream:
          if (_userCtrl.text.trim().isEmpty ||
              _passCtrl.text.trim().isEmpty) {
            _toast('Kullanici adi + sifre gerekli.');
            return;
          }
          username = _userCtrl.text.trim();
          password = _passCtrl.text;
        case PlaylistKind.stalker:
          if (!StalkerClient.isValidMac(_macCtrl.text.trim())) {
            _toast('MAC formati: 00:1A:79:XX:XX:XX');
            return;
          }
          username = StalkerClient.normaliseMac(_macCtrl.text.trim());
          password = 'Europe/Istanbul';
      }
      final source = PlaylistSource(
        id: const Uuid().v4(),
        name: name,
        kind: _kind,
        url: url,
        addedAt: DateTime.now(),
        username: username,
        password: password,
        epgUrl: _epgCtrl.text.trim().isEmpty ? null : _epgCtrl.text.trim(),
      );
      await ref.read(playlistServiceProvider).add(source);
      ref
        ..invalidate(playlistsProvider)
        ..invalidate(allChannelsProvider);
      if (!mounted) return;
      _toast('"${source.name}" eklendi.');
      _next();
    } on Object catch (e) {
      _toast('Eklenemedi: $e');
    } finally {
      if (mounted) setState(() => _busyAdding = false);
    }
  }

  Future<void> _finish() async {
    try {
      await ref
          .read(awatvStorageProvider)
          .prefsBox
          .put(_kOnboardingDoneKey, 'completed');
    } on Object {
      // Persisting completion is best-effort — the playlist redirect
      // does the heavy lifting.
    }
    if (!mounted) return;
    context.go('/home');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(msg),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.stepIndex, required this.total});

  final int stepIndex;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceL,
        DesignTokens.spaceM,
        DesignTokens.spaceL,
        DesignTokens.spaceXs,
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < total; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= stepIndex
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepWelcome extends StatelessWidget {
  const _StepWelcome({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Spacer(),
          Center(
            child: Container(
              width: 168,
              height: 168,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: BrandColors.brandGradient,
              ),
              child: const Icon(
                Icons.live_tv_rounded,
                size: 88,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceXl),
          Text(
            'AWAtv ye hosgeldin',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceS),
          Text(
            'Tek uygulamada canli kanallar, filmler ve diziler. '
            'Senin listen, senin kontrolun.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text('onboarding.continue_button'.tr()),
          ),
          const SizedBox(height: DesignTokens.spaceM),
        ],
      ),
    );
  }
}

/// GDPR-compliant privacy / consent step.
///
/// Old behaviour (≤v0.5.5) was non-compliant:
///   * Toggles default OFF ✅
///   * Toggle changes were NOT persisted (set-but-forgotten) ❌
///   * "Atla" button bypassed the choice → implicit consent ❌
///   * Single union flag governed both Crashlytics + Analytics
///     (no granular consent under GDPR Art. 7(2)) ❌
///   * No link to a privacy policy → fails GDPR Art. 13 transparency ❌
///
/// New behaviour:
///   * Each toggle persists to its own Hive key on the same tick the
///     user flips it (via `AwatvObservability.setCrashlyticsOptIn` /
///     `setAnalyticsOptIn`). Even a force-quit between toggle and
///     "Devam" survives — the choice is captured.
///   * No "Atla" — only "Hepsini Reddet" (explicit refusal, both
///     toggles forced to false) and "Seçimimle Devam" (respects the
///     current toggle state) buttons. Both are valid GDPR consent
///     responses; what's NOT allowed is silent dismissal.
///   * Link to the privacy policy — copied to clipboard on tap (no
///     extra plugin dependency) so the user can paste it in any
///     browser of their choosing.
///   * Hint that the choice is reversible from Ayarlar → Gizlilik.
class _StepPrivacy extends ConsumerStatefulWidget {
  const _StepPrivacy({required this.onContinue});

  final VoidCallback onContinue;

  @override
  ConsumerState<_StepPrivacy> createState() => _StepPrivacyState();
}

class _StepPrivacyState extends ConsumerState<_StepPrivacy> {
  // Initial values come from Hive — if the user is re-running
  // onboarding (e.g. after `rm -rf awatv-storage`), we honour any
  // previously-persisted preference.
  bool _crashlytics = false;
  bool _analytics = false;
  bool _hydrated = false;

  // The published privacy policy lives at this URL. Hosted on the
  // same Cloudflare Pages domain that serves the web build so the
  // user can land there with a single browser tap.
  static const String _kPrivacyPolicyUrl = 'https://awatv.pages.dev/privacy';

  @override
  void initState() {
    super.initState();
    // Read once on mount — no need to ref.watch since we own the local
    // state for the duration of the step.
    _crashlytics = AwatvObservability.readCrashlyticsOptIn();
    _analytics = AwatvObservability.readAnalyticsOptIn();
    _hydrated = true;
  }

  Future<void> _setCrashlytics(bool v) async {
    setState(() => _crashlytics = v);
    await ref
        .read(observabilityOptInProvider.notifier)
        .setCrashlyticsOptIn(v);
  }

  Future<void> _setAnalytics(bool v) async {
    setState(() => _analytics = v);
    await ref
        .read(observabilityOptInProvider.notifier)
        .setAnalyticsOptIn(v);
  }

  Future<void> _rejectAll() async {
    setState(() {
      _crashlytics = false;
      _analytics = false;
    });
    await ref
        .read(observabilityOptInProvider.notifier)
        .setCrashlyticsOptIn(false);
    await ref
        .read(observabilityOptInProvider.notifier)
        .setAnalyticsOptIn(false);
    if (!mounted) return;
    widget.onContinue();
  }

  /// Open the privacy policy URL. Uses platform-native commands rather
  /// than pulling in `url_launcher` for a one-off button — keeps the
  /// dependency graph tight. Falls back to clipboard copy if the
  /// platform can't open URLs (e.g. unprivileged sandboxed sub-process).
  Future<void> _openPrivacyPolicy() async {
    var launched = false;
    try {
      if (kIsWeb) {
        // Can't reach Process on web. Fall through to clipboard.
      } else if (Platform.isMacOS) {
        final r = await Process.run('open', <String>[_kPrivacyPolicyUrl]);
        launched = r.exitCode == 0;
      } else if (Platform.isWindows) {
        final r = await Process.run(
          'cmd',
          <String>['/c', 'start', '', _kPrivacyPolicyUrl],
        );
        launched = r.exitCode == 0;
      } else if (Platform.isLinux) {
        final r = await Process.run('xdg-open', <String>[_kPrivacyPolicyUrl]);
        launched = r.exitCode == 0;
      }
    } on Object {
      // ignore — fall through to clipboard
    }
    if (!launched) {
      await Clipboard.setData(
        const ClipboardData(text: _kPrivacyPolicyUrl),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gizlilik politikası bağlantısı panoya kopyalandı.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (!_hydrated) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignTokens.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Icon(
            Icons.lock_outline_rounded,
            size: 64,
            color: scheme.primary,
          ),
          const SizedBox(height: DesignTokens.spaceM),
          Text(
            'Gizliliğin önceliğimiz',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceS),
          Text(
            'Listen ve favori kanalların bu cihazda kalır. '
            'Aşağıdaki iki teknik veri toplama kanalını ayrı ayrı '
            'kontrol edebilirsin — bu seçimleri istediğin zaman '
            'Ayarlar → Gizlilik üzerinden değiştirebilirsin.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          // -----------------------------------------------------------
          // GDPR-granular toggles — each one persists to its own
          // Hive key on every change.
          // -----------------------------------------------------------
          _ConsentTile(
            icon: Icons.bug_report_outlined,
            title: 'Çökme raporları',
            subtitle:
                'Uygulama beklenmedik şekilde kapanırsa stack trace + '
                "cihaz / OS sürümü Firebase Crashlytics'e iletilir. "
                'IP, e-posta veya kullanım davranışı paylaşılmaz.',
            value: _crashlytics,
            onChanged: _setCrashlytics,
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          _ConsentTile(
            icon: Icons.insights_outlined,
            title: 'Anonim kullanım istatistikleri',
            subtitle:
                'Hangi ekranların ne sıklıkta ziyaret edildiği, hangi '
                'özelliklerin kullanıldığı (kişisel veri olmadan, '
                "cihaz başına anonim ID ile) Firebase Analytics'e "
                'iletilir. Sadece ürün önceliklerini şekillendirmek için.',
            value: _analytics,
            onChanged: _setAnalytics,
          ),
          const SizedBox(height: DesignTokens.spaceM),
          // Privacy policy link — required for GDPR Art. 13.
          Row(
            children: <Widget>[
              const Icon(Icons.policy_outlined, size: 18),
              const SizedBox(width: DesignTokens.spaceS),
              Expanded(
                child: TextButton(
                  onPressed: _openPrivacyPolicy,
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text(
                    'Gizlilik politikasını oku',
                    style: TextStyle(decoration: TextDecoration.underline),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceL),
          // -----------------------------------------------------------
          // Explicit-choice CTAs. NO "Atla" button — that would be
          // implicit consent and is invalid under GDPR.
          // -----------------------------------------------------------
          FilledButton.icon(
            onPressed: widget.onContinue,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Seçimimle devam et'),
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          OutlinedButton.icon(
            onPressed: _rejectAll,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.block_rounded),
            label: const Text('Hepsini reddet ve devam'),
          ),
        ],
      ),
    );
  }
}

/// Reusable consent row used in the privacy step. Visually a card
/// with an icon, title, longer subtitle, and a switch — designed to
/// give the user enough context to make an informed GDPR-grade choice
/// without bouncing to a separate page.
class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 28, color: scheme.primary),
          const SizedBox(width: DesignTokens.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DesignTokens.spaceS),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _StepNotifications extends StatelessWidget {
  const _StepNotifications({
    required this.granted,
    required this.onAsk,
    required this.onNext,
    required this.onSkip,
  });

  final bool? granted;
  final Future<void> Function() onAsk;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusLabel = granted == null
        ? 'Henuz istemedik'
        : granted!
            ? 'Izin verildi'
            : 'Izin reddedildi';
    final statusColor = granted == null
        ? scheme.onSurface.withValues(alpha: 0.6)
        : granted!
            ? Colors.greenAccent
            : Colors.redAccent;
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Icon(
            Icons.notifications_active_outlined,
            size: 64,
            color: scheme.primary,
          ),
          const SizedBox(height: DesignTokens.spaceM),
          Text(
            'Programlari kacirma',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceS),
          Text(
            'Macin baslamasina 5 dakika kalinca, akilli uyarilar '
            'tetiklendiginde ya da bir hatirlatmaya tekrar gelmen '
            'gerektiginde sana cumhurbiz.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
              vertical: DesignTokens.spaceS,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.shield_outlined, color: statusColor),
                const SizedBox(width: DesignTokens.spaceS),
                Expanded(
                  child: Text(
                    'Durum: $statusLabel',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: granted ?? false
                ? onNext
                : () async {
                    await onAsk();
                  },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: Icon(
              granted ?? false
                  ? Icons.arrow_forward_rounded
                  : Icons.notifications_rounded,
            ),
            label: Text(
              granted ?? false ? 'onboarding.continue_button'.tr() : 'Bildirim izni iste',
            ),
          ),
          TextButton(
            onPressed: onSkip,
            child: Text('onboarding.skip_now'.tr()),
          ),
        ],
      ),
    );
  }
}

class _StepFirstPlaylist extends ConsumerWidget {
  const _StepFirstPlaylist({
    required this.kind,
    required this.nameCtrl,
    required this.urlCtrl,
    required this.userCtrl,
    required this.passCtrl,
    required this.macCtrl,
    required this.epgCtrl,
    required this.busy,
    required this.onKindChanged,
    required this.onSubmit,
    required this.onPrefill,
  });

  final PlaylistKind kind;
  final TextEditingController nameCtrl;
  final TextEditingController urlCtrl;
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final TextEditingController macCtrl;
  final TextEditingController epgCtrl;
  final bool busy;
  final ValueChanged<PlaylistKind> onKindChanged;
  final Future<void> Function() onSubmit;
  final ValueChanged<DiscoveredIptvServer> onPrefill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final discoveryAsync = ref.watch(localIptvDiscoveryProvider);
    // Detect signed-in state so we can surface a "bulutla yedeklenecek"
    // hint — the cloud sync engine kicks in automatically on auth and
    // pushes new playlist sources to Supabase, so the user only has to
    // enter their list once across all their devices.
    final isCloudSynced =
        ref.watch(authControllerProvider).valueOrNull is AuthSignedIn;
    return AbsorbPointer(
      absorbing: busy,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Ilk listeni ekle',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceS),
            Text(
              'M3U / Xtream Codes / Stalker Portal — hangi formatla '
              'kullaniyorsan onu seç. Aglarin algilanan IPTV cihazlari '
              'asagida gorunur.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
            if (isCloudSynced) ...<Widget>[
              const SizedBox(height: DesignTokens.spaceS),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceM,
                  vertical: DesignTokens.spaceS,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusM),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.32),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.cloud_done_rounded,
                        color: theme.colorScheme.primary, size: 18),
                    const SizedBox(width: DesignTokens.spaceS),
                    Expanded(
                      child: Text(
                        'Listen otomatik olarak hesabına yedeklenecek '
                        '— diğer cihazlarında tekrar tanıtmana gerek yok.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: DesignTokens.spaceM),
            // Bonjour-discovered server suggestions row.
            discoveryAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (Object _, StackTrace __) => const SizedBox.shrink(),
              data: (List<DiscoveredIptvServer> servers) {
                if (servers.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: DesignTokens.spaceM,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Aginda algilanan cihazlar',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spaceS),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final s in servers)
                            ActionChip(
                              avatar: const Icon(Icons.dns_rounded, size: 16),
                              label: Text(
                                '${s.name} (${s.host}:${s.port})',
                              ),
                              onPressed: () => onPrefill(s),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            SegmentedButton<PlaylistKind>(
              segments: const <ButtonSegment<PlaylistKind>>[
                ButtonSegment<PlaylistKind>(
                  value: PlaylistKind.m3u,
                  label: Text('M3U'),
                  icon: Icon(Icons.list_alt_rounded),
                ),
                ButtonSegment<PlaylistKind>(
                  value: PlaylistKind.xtream,
                  label: Text('Xtream'),
                  icon: Icon(Icons.vpn_key_outlined),
                ),
                ButtonSegment<PlaylistKind>(
                  value: PlaylistKind.stalker,
                  label: Text('Stalker'),
                  icon: Icon(Icons.dns_outlined),
                ),
              ],
              selected: <PlaylistKind>{kind},
              onSelectionChanged: (Set<PlaylistKind> set) =>
                  onKindChanged(set.first),
            ),
            const SizedBox(height: DesignTokens.spaceM),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Liste adi',
                hintText: 'Ornek: Evdeki IPTV',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceM),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: kind == PlaylistKind.m3u
                    ? 'M3U / M3U8 URL'
                    : kind == PlaylistKind.xtream
                        ? 'Sunucu URL'
                        : 'Portal URL',
                hintText: 'http://...',
                border: const OutlineInputBorder(),
              ),
            ),
            if (kind == PlaylistKind.xtream) ...<Widget>[
              const SizedBox(height: DesignTokens.spaceM),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kullanici adi',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: DesignTokens.spaceM),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Sifre',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (kind == PlaylistKind.stalker) ...<Widget>[
              const SizedBox(height: DesignTokens.spaceM),
              TextField(
                controller: macCtrl,
                decoration: const InputDecoration(
                  labelText: 'MAC adresi',
                  hintText: '00:1A:79:XX:XX:XX',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (kind == PlaylistKind.m3u || kind == PlaylistKind.xtream) ...<Widget>[
              const SizedBox(height: DesignTokens.spaceM),
              TextField(
                controller: epgCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'EPG URL (opsiyonel)',
                  hintText: 'http://example.com/epg.xml',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: DesignTokens.spaceXl),
            FilledButton.icon(
              onPressed: busy ? null : onSubmit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_link_rounded),
              label: Text(busy ? 'Ekleniyor...' : 'Listemi ekle'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepAllSet extends StatelessWidget {
  const _StepAllSet({required this.onFinish});

  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Spacer(),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            tween: Tween<double>(begin: 0, end: 1),
            builder: (BuildContext _, double value, Widget? __) {
              return Transform.scale(
                scale: value,
                child: Center(
                  child: Container(
                    width: 168,
                    height: 168,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: <Color>[
                          theme.colorScheme.primary,
                          theme.colorScheme.tertiary,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 96,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: DesignTokens.spaceXl),
          Text(
            'Hazir',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceS),
          Text(
            'Listen yuklendi. Anasayfada kategori agacindan baslayabilir, '
            'TV Rehberinden hatirlatma kurabilirsin.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () async => onFinish(),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.rocket_launch_rounded),
            label: Text('onboarding.wizard_lets_start'.tr()),
          ),
          const SizedBox(height: DesignTokens.spaceM),
        ],
      ),
    );
  }
}

/// Step 2 — Sign in / Sign up. Three modes co-located in a single
/// screen so the user doesn't have to bounce to /login and back:
///
///   * **Giriş Yap** tab — email + password, calls
///     `signInWithPassword`. Falls through to "auto-advance to next
///     step" once the auth controller emits `AuthSignedIn`.
///   * **Hesap Oluştur** tab — email + password (≥6), calls
///     `signUpWithPassword`. Same auto-advance.
///   * **Misafir Devam Et** ghost button — bypasses auth entirely;
///     local-only mode. Cloud sync stays off, playlists stay on
///     this device.
///
/// When `Env.hasSupabase` is false the form switches to a static
/// "yapılandırılmadı" panel — auth is unavailable in this build, only
/// Misafir mode is offered.
class _StepAuth extends ConsumerStatefulWidget {
  const _StepAuth({required this.onNext, required this.onSkip});

  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  ConsumerState<_StepAuth> createState() => _StepAuthState();
}

enum _AuthMode { signIn, signUp }

class _StepAuthState extends ConsumerState<_StepAuth> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  bool _passwordVisible = false;
  String? _error;
  // Track whether we've already auto-advanced to the next step so that
  // re-entering this step (via Geri) doesn't immediately bounce back.
  bool _advancedOnce = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _emailCtrl.text.trim();
    final pw = _passCtrl.text;
    try {
      final notifier = ref.read(authControllerProvider.notifier);
      if (_mode == _AuthMode.signIn) {
        await notifier.signInWithPassword(email: email, password: pw);
      } else {
        await notifier.signUpWithPassword(email: email, password: pw);
      }
      if (!mounted) return;
      // Don't navigate here — the auth controller's stream emits
      // AuthSignedIn on the next tick and the listen() callback in
      // build() forwards via widget.onNext.
    } on AuthBackendNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Bulut yedeği yapılandırılmadı.';
      });
    } on supa.AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasBackend = Env.hasSupabase;

    // Auto-advance once auth state flips to signed-in. We listen rather
    // than build-watch so a sign-out somewhere else doesn't trigger an
    // unwanted state change here.
    ref.listen<AsyncValue<AuthState>>(
      authControllerProvider,
      (AsyncValue<AuthState>? prev, AsyncValue<AuthState> next) {
        if (_advancedOnce) return;
        if (next.valueOrNull is AuthSignedIn) {
          _advancedOnce = true;
          widget.onNext();
        }
      },
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignTokens.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Icon(
            Icons.cloud_sync_rounded,
            size: 64,
            color: scheme.primary,
          ),
          const SizedBox(height: DesignTokens.spaceM),
          Text(
            'Hesabınla giriş yap',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          Text(
            'Listenler ve favorilerin tüm cihazlarda otomatik '
            'yedeklenir; her kurulumda tekrar tekrar listeyi '
            'eklemen gerekmez.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          if (!hasBackend) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              decoration: BoxDecoration(
                color: BrandColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(DesignTokens.radiusM),
                border: Border.all(
                  color: BrandColors.warning.withValues(alpha: 0.48),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.cloud_off_outlined,
                      color: BrandColors.warning),
                  const SizedBox(width: DesignTokens.spaceM),
                  Expanded(
                    child: Text(
                      'Bu yapıda bulut yedeği yapılandırılmadı. '
                      'Misafir olarak devam et — listen yine de '
                      'cihazında saklanır.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.spaceL),
          ] else ...<Widget>[
            // Mode toggle — Sign In / Sign Up
            SegmentedButton<_AuthMode>(
              segments: const <ButtonSegment<_AuthMode>>[
                ButtonSegment<_AuthMode>(
                  value: _AuthMode.signIn,
                  label: Text('Giriş Yap'),
                  icon: Icon(Icons.login_rounded),
                ),
                ButtonSegment<_AuthMode>(
                  value: _AuthMode.signUp,
                  label: Text('Hesap Oluştur'),
                  icon: Icon(Icons.person_add_alt_1_rounded),
                ),
              ],
              selected: <_AuthMode>{_mode},
              onSelectionChanged: (Set<_AuthMode> set) => setState(() {
                _mode = set.first;
                _error = null;
              }),
            ),
            const SizedBox(height: DesignTokens.spaceM),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextFormField(
                    controller: _emailCtrl,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const <String>[AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (String? v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'E-posta gerekli';
                      if (!t.contains('@') || !t.contains('.')) {
                        return 'Geçerli bir e-posta gir';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: DesignTokens.spaceM),
                  TextFormField(
                    controller: _passCtrl,
                    enabled: !_busy,
                    obscureText: !_passwordVisible,
                    autofillHints: _mode == _AuthMode.signIn
                        ? const <String>[AutofillHints.password]
                        : const <String>[AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Şifre',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_passwordVisible
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded),
                        onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible),
                      ),
                      border: const OutlineInputBorder(),
                      helperText: _mode == _AuthMode.signUp
                          ? 'En az 6 karakter'
                          : null,
                    ),
                    validator: (String? v) {
                      final t = v ?? '';
                      if (t.isEmpty) return 'Şifre gerekli';
                      if (_mode == _AuthMode.signUp && t.length < 6) {
                        return 'En az 6 karakter';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                  ),
                ],
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: DesignTokens.spaceM),
              Container(
                padding: const EdgeInsets.all(DesignTokens.spaceM),
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusM),
                  border: Border.all(
                    color: scheme.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.error_outline_rounded,
                        size: 18, color: scheme.error),
                    const SizedBox(width: DesignTokens.spaceS),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: DesignTokens.spaceL),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_mode == _AuthMode.signIn
                      ? Icons.login_rounded
                      : Icons.person_add_alt_1_rounded),
              label: Text(_busy
                  ? (_mode == _AuthMode.signIn
                      ? 'Giriş yapılıyor…'
                      : 'Hesap oluşturuluyor…')
                  : (_mode == _AuthMode.signIn
                      ? 'Giriş Yap'
                      : 'Hesap Oluştur')),
            ),
          ],
          const SizedBox(height: DesignTokens.spaceM),
          TextButton.icon(
            onPressed: widget.onSkip,
            icon: const Icon(Icons.no_accounts_outlined),
            label: const Text('Misafir olarak devam et'),
          ),
        ],
      ),
    );
  }
}

/// Step 6 — Premium teaser. Quick pitch of the paid features the user
/// will encounter once they leave onboarding (the player's "kilitli"
/// badges, the recordings tab, the family-sharing option, etc.). Two
/// outs: "Detaylar" → /premium full pitch, or "Daha Sonra" to skip.
///
/// Intentionally not a hard paywall — the app is freemium, not pay-to-
/// play. Users who never click anything still get a working IPTV
/// player. The teaser exists so they discover the upgrade exists.
class _StepPremium extends StatelessWidget {
  const _StepPremium({required this.onNext, required this.onSkip});

  final VoidCallback onNext;
  final VoidCallback onSkip;

  static const List<_PremiumPerk> _kPerks = <_PremiumPerk>[
    _PremiumPerk(Icons.auto_awesome_rounded, 'Reklamsız oynatma'),
    _PremiumPerk(Icons.fiber_smart_record_rounded, 'Bulut kayıtları (DVR)'),
    _PremiumPerk(Icons.subtitles_rounded, 'Akıllı altyazı arama'),
    _PremiumPerk(Icons.headset_mic_rounded, 'Arka planda dinleme'),
    _PremiumPerk(Icons.download_for_offline_rounded, 'Çevrimdışı indirme'),
    _PremiumPerk(Icons.high_quality_rounded, '4K + HDR pas geçme'),
    _PremiumPerk(Icons.family_restroom_rounded, 'Aile paylaşımı'),
    _PremiumPerk(Icons.notifications_active_rounded, 'Akıllı uyarılar'),
    _PremiumPerk(Icons.support_agent_rounded, '7/24 öncelikli destek'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignTokens.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceM,
                vertical: DesignTokens.spaceXs,
              ),
              decoration: BoxDecoration(
                gradient: BrandColors.brandGradient,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'PREMIUM',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceM),
          Text(
            'Daha fazlası mevcut',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          Text(
            'Premium üyelik AWAtv deneyimini bir adım öteye taşır. '
            'Aşağıdaki özellikler kilitli olarak işaretlenir; '
            'dilediğin zaman aboneliği başlatabilirsin.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          // Two-column grid of feature chips on wider screens, list on phones.
          LayoutBuilder(
            builder: (BuildContext _, BoxConstraints constraints) {
              final isWide = constraints.maxWidth > 480;
              final cross = isWide ? 2 : 1;
              return GridView.count(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                crossAxisCount: cross,
                crossAxisSpacing: DesignTokens.spaceS,
                mainAxisSpacing: DesignTokens.spaceS,
                childAspectRatio: isWide ? 5.0 : 7.0,
                children: <Widget>[
                  for (final p in _kPerks)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spaceM,
                        vertical: DesignTokens.spaceXs,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusM),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(p.icon, color: scheme.primary, size: 20),
                          const SizedBox(width: DesignTokens.spaceS),
                          Expanded(
                            child: Text(
                              p.label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: DesignTokens.spaceL),
          FilledButton.icon(
            onPressed: () {
              // Push the full /premium screen. After dismiss the wizard
              // resumes at this step — caller can tap Continue when done.
              GoRouter.of(context).push('/premium');
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Detaylar ve fiyatlar'),
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          TextButton(
            onPressed: onSkip,
            child: const Text('Daha sonra inceleyelim'),
          ),
        ],
      ),
    );
  }
}

class _PremiumPerk {
  const _PremiumPerk(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Helper: did the user already finish the wizard? Used by the
/// router to decide whether `/onboarding` shows the legacy welcome
/// (skips wizard) or pushes the wizard.
bool isOnboardingCompleted(AwatvStorage storage) {
  try {
    final raw = storage.prefsBox.get(_kOnboardingDoneKey);
    return raw is String && raw.isNotEmpty;
  } on Object {
    return false;
  }
}
