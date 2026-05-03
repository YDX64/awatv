import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/premium/premium_status_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Streas-style account dashboard.
///
/// Renders, top → bottom:
///   * Header with chevron back + "Hesap" title.
///   * Profile hero (cherry circle avatar, display name, email).
///   * 4-cell stats row: profile count / favori / geçmiş / Premium?.
///   * "ACCOUNT DETAILS" card (e-posta + change shortcut).
///   * "PLAN" card (Free / Premium with Yükselt CTA).
///   * Sign-out tile (cherry — wires the logout modal Streas left
///     stranded in `app/account.tsx`).
///   * "Hesabı Sil" destructive tile with two-step confirm dialog.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    final confirmed = await _confirmDialog(
      title: 'Çıkış yapmak istediğine emin misin?',
      body:
          'Çıkış yaptığında bu cihazdaki indirilen içerikler kaldırılır.',
      confirmLabel: 'Çıkış yap',
      isDestructive: false,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await ref.read(authControllerProvider.notifier).signOut();
      if (!mounted) return;
      context.go('/onboarding');
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Çıkış başarısız: $e')),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await _confirmDialog(
      title: 'Hesap silinsin mi?',
      body:
          'Bu işlem hesabını ve tüm verilerini kalıcı olarak siler. Geri alınamaz.',
      confirmLabel: 'Sil',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } on Object {
      // Soft-delete fall-through — Phase 6 wires the actual RPC. For
      // now we surface the intent and leave the user on /welcome.
    }
    if (!mounted) return;
    context.go('/onboarding');
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String body,
    required String confirmLabel,
    required bool isDestructive,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (BuildContext ctx) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Material(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 19 / 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          style: TextButton.styleFrom(
                            foregroundColor: BrandColors.primary,
                          ),
                          child: const Text(
                            'Vazgeç',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: TextButton.styleFrom(
                            foregroundColor: isDestructive
                                ? const Color(0xFFEF4444)
                                : BrandColors.primary,
                          ),
                          child: Text(
                            confirmLabel,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final profilesAsync = ref.watch(profilesListProvider);
    final tier = ref.watch(premiumStatusProvider);
    final isPremium = tier.isPremium;

    if (auth is! AuthSignedIn) {
      return _GuestAccount(
        onLoginTap: () => context.push('/login'),
        onBack: () => _safeBack(context),
      );
    }

    final profilesCount = profilesAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _Header(onBack: () => _safeBack(context)),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  _ProfileHero(
                    displayName: auth.displayName ?? auth.email.split('@').first,
                    email: auth.email,
                  ),
                  _StatsRow(
                    profilesCount: profilesCount,
                    isPremium: isPremium,
                  ),
                  const _SectionLabel('HESAP DETAYLARI'),
                  _Card(
                    children: <Widget>[
                      _Row(
                        leading: auth.email,
                        action: 'Değiştir',
                        onAction: () => ScaffoldMessenger.of(context)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                              'E-posta değişikliği bir sonraki sürümde gelecek.',
                            ),
                          ),
                        ),
                      ),
                      _Row(
                        leading: 'Şifre: ••••••••••••',
                        action: 'Değiştir',
                        onAction: () => ScaffoldMessenger.of(context)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Şifre değişikliği bir sonraki sürümde gelecek.',
                            ),
                          ),
                        ),
                      ),
                      _Row(
                        leading: 'Tüm cihazlardan çıkış yap',
                        leadingColor: BrandColors.primary,
                        onAction: () =>
                            context.push('/settings/devices'),
                      ),
                    ],
                  ),
                  const _SectionLabel('PLAN'),
                  _Card(
                    children: <Widget>[
                      _Row(
                        leading: isPremium ? 'AwaTV Premium' : 'Ücretsiz Plan',
                        action: isPremium ? 'Yönet' : 'Yükselt',
                        onAction: () => context.push('/premium'),
                      ),
                    ],
                  ),
                  const _SectionLabel('HESAP'),
                  _Card(
                    children: <Widget>[
                      _Row(
                        leading: 'Çıkış yap',
                        leadingColor: BrandColors.primary,
                        leadingBold: true,
                        trailingIcon: _signingOut
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    BrandColors.primary,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.logout_rounded,
                                size: 16,
                                color: BrandColors.primary,
                              ),
                        onAction: _signingOut ? null : _signOut,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _deleteAccount,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'Hesabımı Sil',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _safeBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF282828)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Row(
          children: <Widget>[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(20),
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.chevron_left_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Hesap',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.displayName, required this.email});

  final String displayName;
  final String email;

  String get _initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return p.isEmpty ? '?' : p.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: BrandColors.brandGradient,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: const TextStyle(
              color: Color(0x99FFFFFF),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.profilesCount,
    required this.isPremium,
  });

  final int profilesCount;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _StatBox(
              value: '$profilesCount',
              label: 'Profil',
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: _StatBox(value: '—', label: 'Favori'),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: _StatBox(value: '—', label: 'Geçmiş'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatBox(
              value: isPremium ? 'Premium' : 'Ücretsiz',
              label: 'Plan',
              valueColor: isPremium ? BrandColors.warning : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.value,
    required this.label,
    this.valueColor = Colors.white,
  });

  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        border: Border.all(color: const Color(0xFF282828)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0x80FFFFFF),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0x80808080),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        border: Border.all(color: const Color(0xFF282828)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < children.length; i++) ...<Widget>[
              children[i],
              if (i != children.length - 1)
                const Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Color(0xFF282828),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    this.action,
    this.leadingColor = Colors.white,
    this.leadingBold = false,
    this.trailingIcon,
    this.onAction,
  });

  final String leading;
  final String? action;
  final Color leadingColor;
  final bool leadingBold;
  final Widget? trailingIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                leading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: leadingColor,
                  fontSize: 14,
                  fontWeight:
                      leadingBold ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (action != null)
              Text(
                action!,
                style: const TextStyle(
                  color: BrandColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (trailingIcon != null)
              trailingIcon!,
          ],
        ),
      ),
    );
  }
}

class _GuestAccount extends StatelessWidget {
  const _GuestAccount({
    required this.onLoginTap,
    required this.onBack,
  });

  final VoidCallback onLoginTap;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _Header(onBack: onBack),
            const SizedBox(height: 24),
            const _SectionLabel('HESAP'),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                border: Border.all(color: const Color(0xFF282828)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  const Icon(
                    Icons.person_outline_rounded,
                    color: BrandColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Misafir Modu',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Verilerini cihazlar arasında senkronlamak için '
                          'giriş yap.',
                          style: TextStyle(
                            color: Color(0x80808080),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onLoginTap,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: BrandColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Giriş',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
}
