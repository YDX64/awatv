import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/playlists/playlist_providers.dart';
import 'package:awatv_mobile/src/shared/discovery/discovered_iptv_server.dart';
import 'package:awatv_mobile/src/shared/discovery/local_iptv_discovery.dart';
import 'package:awatv_mobile/src/shared/notifications/notifications_provider.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

/// Hive prefs key tracking how far through the wizard the user has
/// progressed. Empty / "false" → still pending; "completed" → wizard
/// has been finished and the regular onboarding redirect skips it.
const String _kOnboardingDoneKey = 'prefs:onboarding.completed';

/// Five-step onboarding wizard.
///
/// Steps:
///   1. **Welcome** — brand hero + tagline + "Devam"
///   2. **Privacy** — Crashlytics + Analytics opt-in toggles
///   3. **Notifications** — request OS notification permission
///   4. **First playlist** — M3U / Xtream / Stalker form + Bonjour
///      discovery preview (cannot skip — adding a source is the only
///      way out)
///   5. **All set** — success animation + "Hadi baslayalim" → /home
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

  // Step 2 (privacy) — opt-ins default to "off"; user explicitly
  // ticks them to enable. We do not auto-enable analytics.
  bool _crashlytics = false;
  bool _analytics = false;

  // Step 3 — notification permission outcome.
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

  static const int _kStepCount = 5;

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
                  _StepPrivacy(
                    crashlytics: _crashlytics,
                    analytics: _analytics,
                    onCrashlytics: (bool v) =>
                        setState(() => _crashlytics = v),
                    onAnalytics: (bool v) => setState(() => _analytics = v),
                    onNext: _next,
                    onSkip: _next,
                  ),
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

class _StepPrivacy extends StatelessWidget {
  const _StepPrivacy({
    required this.crashlytics,
    required this.analytics,
    required this.onCrashlytics,
    required this.onAnalytics,
    required this.onNext,
    required this.onSkip,
  });

  final bool crashlytics;
  final bool analytics;
  final ValueChanged<bool> onCrashlytics;
  final ValueChanged<bool> onAnalytics;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Icon(
            Icons.lock_outline_rounded,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: DesignTokens.spaceM),
          Text(
            'Gizliligin onceligimiz',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceS),
          Text(
            'Listen bu cihazda kalir. Gelistirmemize katki saglamak '
            'istersen iki teknik veriyi paylasabilirsin — istediginde '
            'Ayarlardan kapatabilirsin.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          SwitchListTile.adaptive(
            value: crashlytics,
            onChanged: onCrashlytics,
            title: Text('onboarding.wizard_crash_reports_title'.tr()),
            subtitle: const Text(
              'Beklenmedik kapanmalari Sentry uzerinden bildirelim.',
            ),
          ),
          SwitchListTile.adaptive(
            value: analytics,
            onChanged: onAnalytics,
            title: Text('onboarding.wizard_anon_usage_title'.tr()),
            subtitle: const Text(
              'Hangi ekranlarin populer oldugunu kisisel veri olmadan paylas.',
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
          TextButton(
            onPressed: onSkip,
            child: Text('onboarding.skip_now'.tr()),
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
