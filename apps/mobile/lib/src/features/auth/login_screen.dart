import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/features/onboarding/welcome_screen.dart'
    show GradientCta, StreasInput, resolvePostLoginDestination;
import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// Streas-style 2-step email→password login.
///
/// Step 1 collects + validates the email; tapping "Devam" locks the
/// email field and reveals the password field plus "Şifremi unuttum"
/// link. Tapping "Giriş yap" submits credentials to Supabase via the
/// existing [authControllerProvider]. The legacy magic-link path is
/// preserved behind a small footer toggle so users on hand-provisioned
/// accounts can still receive a one-time link.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({this.next, super.key});

  final String? next;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _LoginStep { email, password }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  _LoginStep _step = _LoginStep.email;
  bool _passwordVisible = false;
  bool _magicLinkMode = false;
  bool _loading = false;
  String? _error;
  String? _magicLinkSentTo;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _handleEmailContinue() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Geçerli bir e-posta adresi gir.');
      return;
    }
    setState(() {
      _error = null;
      _step = _LoginStep.password;
    });
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _passwordFocus.requestFocus();
    });
  }

  Future<void> _handleSignIn() async {
    final pw = _passwordController.text;
    if (pw.isEmpty) {
      setState(() => _error = 'Şifreni gir.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signInWithPassword(
            email: _emailController.text.trim(),
            password: pw,
          );
      if (!mounted) return;
      // Surface a brief success toast before navigating so the user
      // gets explicit confirmation that the credentials worked. The
      // toast persists across the route push thanks to ScaffoldMessenger
      // living above the router.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('Giriş başarılı — ana ekrana yönlendiriliyorsun…'),
        ),
      );
      final next = widget.next ?? resolvePostLoginDestination(ref);
      context.go(next);
    } on AuthBackendNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? 'Bulut sunucusu yapılandırılmamış.');
    } on supa.AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Giriş yapılamadı: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleMagicLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Geçerli bir e-posta adresi gir.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).sendMagicLink(email);
      if (!mounted) return;
      setState(() => _magicLinkSentTo = email);
    } on AuthBackendNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? 'Bulut sunucusu yapılandırılmamış.');
    } on supa.AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Bağlantı gönderilemedi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleBack() {
    if (_step == _LoginStep.password) {
      setState(() {
        _step = _LoginStep.email;
        _error = null;
      });
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // ─── Header ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _BackChevron(onTap: _handleBack),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  28,
                  24,
                  28,
                  24 + mediaQuery.viewInsets.bottom,
                ),
                child: _magicLinkSentTo != null
                    ? _MagicLinkSentPanel(
                        email: _magicLinkSentTo!,
                        onWrongEmail: () => setState(() {
                          _magicLinkSentTo = null;
                          _magicLinkMode = false;
                        }),
                      )
                    : _LoginForm(
                        step: _step,
                        emailController: _emailController,
                        passwordController: _passwordController,
                        passwordFocus: _passwordFocus,
                        passwordVisible: _passwordVisible,
                        magicLinkMode: _magicLinkMode,
                        loading: _loading,
                        error: _error,
                        hasBackend: Env.hasSupabase,
                        onEmailChanged: (_) {
                          if (_error != null) {
                            setState(() => _error = null);
                          }
                        },
                        onPasswordChanged: (_) {
                          if (_error != null) {
                            setState(() => _error = null);
                          }
                        },
                        onTogglePasswordVisible: () => setState(() {
                          _passwordVisible = !_passwordVisible;
                        }),
                        onSubmit: () {
                          if (_magicLinkMode) {
                            _handleMagicLink();
                          } else if (_step == _LoginStep.email) {
                            _handleEmailContinue();
                          } else {
                            _handleSignIn();
                          }
                        },
                        onForgotPassword: () => setState(() {
                          _magicLinkMode = true;
                          _step = _LoginStep.email;
                          _error = null;
                        }),
                        onToggleMagicLink: () => setState(() {
                          _magicLinkMode = !_magicLinkMode;
                          _step = _LoginStep.email;
                          _error = null;
                        }),
                        onSignupTap: () => context.push('/signup'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackChevron extends StatelessWidget {
  const _BackChevron({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.step,
    required this.emailController,
    required this.passwordController,
    required this.passwordFocus,
    required this.passwordVisible,
    required this.magicLinkMode,
    required this.loading,
    required this.error,
    required this.hasBackend,
    required this.onEmailChanged,
    required this.onPasswordChanged,
    required this.onTogglePasswordVisible,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onToggleMagicLink,
    required this.onSignupTap,
  });

  final _LoginStep step;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode passwordFocus;
  final bool passwordVisible;
  final bool magicLinkMode;
  final bool loading;
  final String? error;
  final bool hasBackend;
  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String> onPasswordChanged;
  final VoidCallback onTogglePasswordVisible;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onToggleMagicLink;
  final VoidCallback onSignupTap;

  bool get _isPasswordStep => step == _LoginStep.password && !magicLinkMode;

  String get _ctaLabel {
    if (magicLinkMode) return 'BAĞLANTI GÖNDER';
    if (step == _LoginStep.email) return 'DEVAM';
    return 'GİRİŞ YAP';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'E-posta ile giriş yap',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          magicLinkMode
              ? 'E-posta adresine bir oturum bağlantısı gönderelim. Bağlantıya tıklayarak şifresiz giriş yapabilirsin.'
              : 'AwaTV bulut senkronizasyonu için bu e-posta ve şifreyi kullanacaksın.',
          style: const TextStyle(
            color: Color(0x80FFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 20 / 13,
          ),
        ),
        const SizedBox(height: 14),
        if (!hasBackend) const _BackendNotConfiguredBanner(),
        if (!hasBackend) const SizedBox(height: 14),
        StreasInput(
          controller: emailController,
          placeholder: 'E-posta',
          keyboardType: TextInputType.emailAddress,
          autofocus: step == _LoginStep.email && !magicLinkMode,
          locked: _isPasswordStep,
          error: error != null && step == _LoginStep.email,
          onChanged: onEmailChanged,
          onSubmitted: (_) => onSubmit(),
          textInputAction: TextInputAction.next,
        ),
        if (_isPasswordStep) ...<Widget>[
          const SizedBox(height: 14),
          StreasInput(
            controller: passwordController,
            placeholder: 'Şifre',
            obscureText: !passwordVisible,
            error: error != null,
            onChanged: onPasswordChanged,
            onSubmitted: (_) => onSubmit(),
            autofocus: true,
            textInputAction: TextInputAction.done,
            suffix: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTogglePasswordVisible,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  passwordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: const Color(0x66FFFFFF),
                ),
              ),
            ),
          ),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.error_outline_rounded,
                size: 13,
                color: Color(0xFFEF4444),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  error!,
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (_isPasswordStep) ...<Widget>[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onForgotPassword,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Şifremi unuttum',
                  style: TextStyle(
                    color: BrandColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _EmailRecap(email: emailController.text.trim()),
        ],
        const SizedBox(height: 8),
        GradientCta(
          label: _ctaLabel,
          loading: loading,
          onPressed: hasBackend && !loading ? onSubmit : null,
        ),
        const SizedBox(height: 14),
        Center(
          child: GestureDetector(
            onTap: onToggleMagicLink,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                magicLinkMode
                    ? 'Şifre ile giriş yap'
                    : 'Sihirli bağlantı ile giriş yap',
                style: const TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text(
                "AwaTV'de yeni misin? ",
                style: TextStyle(
                  color: Color(0x80FFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              GestureDetector(
                onTap: onSignupTap,
                child: const Text(
                  'KAYIT OL',
                  style: TextStyle(
                    color: BrandColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmailRecap extends StatelessWidget {
  const _EmailRecap({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Bu e-posta ile giriş yapacaksın:',
          style: TextStyle(
            color: Color(0x73FFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          email,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MagicLinkSentPanel extends StatelessWidget {
  const _MagicLinkSentPanel({
    required this.email,
    required this.onWrongEmail,
  });

  final String email;
  final VoidCallback onWrongEmail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'E-postanı kontrol et',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '$email adresine bir oturum bağlantısı gönderdik. Bağlantıya tıklayarak girişi tamamla.',
          style: const TextStyle(
            color: Color(0x80FFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 20 / 13,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: BrandColors.primary.withValues(alpha: 0.08),
            border: Border.all(
              color: BrandColors.primary.withValues(alpha: 0.32),
            ),
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          ),
          child: Column(
            children: <Widget>[
              const Icon(
                Icons.mark_email_read_outlined,
                size: 36,
                color: BrandColors.primary,
              ),
              const SizedBox(height: 10),
              Text(
                email,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Bağlantıyı bekliyoruz…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xA6FFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: onWrongEmail,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Yanlış e-posta?',
                style: TextStyle(
                  color: BrandColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BackendNotConfiguredBanner extends StatelessWidget {
  const _BackendNotConfiguredBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BrandColors.warning.withValues(alpha: 0.12),
        border: Border.all(color: BrandColors.warning.withValues(alpha: 0.48)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: BrandColors.warning,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bulut sunucusu yapılandırılmamış. Ayarlardan Supabase '
              'bilgilerini doldurabilirsin.',
              style: TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 17 / 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
