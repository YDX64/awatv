import 'package:awatv_mobile/src/features/onboarding/welcome_screen.dart'
    show GradientCta, StreasInput, resolvePostLoginDestination;
import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// Streas-style 3-step signup wizard (email → password → display name).
///
/// Step indicator + cherry progress bar mirror the React Native source
/// at `app/signup.tsx`. Streas asks for birthdate in step 3; AWAtv uses
/// the slot for the display name instead — that maps cleanly onto our
/// existing `signUpWithPassword` + `updateDisplayName` calls and avoids
/// a new schema column for `birthdate` we don't currently track.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  static const int _totalSteps = 3;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  int _step = 1;
  bool _passwordVisible = false;
  bool _marketing = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (_step > 1) {
      setState(() {
        _step -= 1;
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

  void _handleStep1() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Geçerli bir e-posta gir.');
      return;
    }
    setState(() {
      _error = null;
      _step = 2;
    });
  }

  void _handleStep2() {
    if (_passwordController.text.length < 6) {
      setState(() => _error = 'Şifre en az 6 karakter olmalı.');
      return;
    }
    setState(() {
      _error = null;
      _step = 3;
    });
  }

  Future<void> _handleStep3() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Görünen ad gerekli.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = ref.read(authControllerProvider.notifier);
      await controller.signUpWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      try {
        await controller.updateDisplayName(name);
      } on Object {
        // Display-name update is best-effort; the account is still
        // created and the user can edit later from Account screen.
      }
      if (!mounted) return;
      context.go(resolvePostLoginDestination(ref));
    } on AuthBackendNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Bulut sunucusu yapılandırılmamış.';
      });
    } on supa.AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Kayıt başarısız: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
            _SignupHeader(step: _step, total: _totalSteps, onBack: _handleBack),
            _ProgressTrack(progress: _step / _totalSteps),
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  28,
                  28,
                  28,
                  40 + mediaQuery.viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'KAYIT OL',
                      style: TextStyle(
                        color: Color(0x66FFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(
                        key: ValueKey<int>(_step),
                        child: _stepBody(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/login');
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                'Zaten hesabın var mı? ',
                                style: TextStyle(
                                  color: Color(0x80FFFFFF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              Text(
                                'GİRİŞ YAP',
                                style: TextStyle(
                                  color: BrandColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 1:
        return _Step1(
          controller: _emailController,
          marketing: _marketing,
          error: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onMarketingToggle: () => setState(() => _marketing = !_marketing),
          onSubmit: _handleStep1,
        );
      case 2:
        return _Step2(
          controller: _passwordController,
          email: _emailController.text.trim(),
          passwordVisible: _passwordVisible,
          error: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
            // Force rebuild to refresh strength meter.
            setState(() {});
          },
          onTogglePasswordVisible: () => setState(() {
            _passwordVisible = !_passwordVisible;
          }),
          onSubmit: _handleStep2,
        );
      case 3:
      default:
        return _Step3(
          controller: _nameController,
          email: _emailController.text.trim(),
          loading: _loading,
          error: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmit: _handleStep3,
        );
    }
  }
}

class _SignupHeader extends StatelessWidget {
  const _SignupHeader({
    required this.step,
    required this.total,
    required this.onBack,
  });

  final int step;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
          Expanded(
            child: Center(
              child: Text(
                'Adım $step / $total',
                style: const TextStyle(
                  color: Color(0x80FFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        value: progress.clamp(0, 1),
        backgroundColor: const Color(0x1AFFFFFF),
        valueColor: const AlwaysStoppedAnimation<Color>(BrandColors.primary),
      ),
    );
  }
}

class _Step1 extends StatelessWidget {
  const _Step1({
    required this.controller,
    required this.marketing,
    required this.error,
    required this.onChanged,
    required this.onMarketingToggle,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool marketing;
  final String? error;
  final ValueChanged<String> onChanged;
  final VoidCallback onMarketingToggle;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'E-postanı gir',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'AwaTV bulut senkronizasyonu için bu e-posta ve şifreyi kullanacaksın.',
          style: TextStyle(
            color: Color(0x80FFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 20 / 13,
          ),
        ),
        const SizedBox(height: 16),
        StreasInput(
          controller: controller,
          placeholder: 'E-posta',
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          error: error != null,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmit(),
          textInputAction: TextInputAction.next,
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _ConsentCheckbox(
          checked: marketing,
          onTap: onMarketingToggle,
          label:
              'Evet, AwaTV güncellemeleri, özel teklifler ve diğer bilgileri almak istiyorum.',
        ),
        const SizedBox(height: 12),
        const _LegalBlob(),
        const SizedBox(height: 16),
        GradientCta(label: 'KABUL ET & DEVAM', onPressed: onSubmit),
      ],
    );
  }
}

class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({
    required this.checked,
    required this.onTap,
    required this.label,
  });

  final bool checked;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(top: 1),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: checked ? BrandColors.primary : Colors.transparent,
              border: Border.all(
                color: checked ? BrandColors.primary : const Color(0x4DFFFFFF),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: checked
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 18 / 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalBlob extends StatelessWidget {
  const _LegalBlob();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: const TextSpan(
        style: TextStyle(
          color: Color(0x66FFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 17 / 11,
        ),
        children: <InlineSpan>[
          TextSpan(
            text:
                'AwaTV deneyimini kişiselleştirmek ve geliştirmek için verilerini kullanır. '
                'Tercihlerini istediğin zaman değiştirebilirsin. "Kabul Et & Devam"a basarak ',
          ),
          TextSpan(
            text: 'Kullanıcı Sözleşmesi',
            style: TextStyle(color: BrandColors.primary),
          ),
          TextSpan(text: ' ve '),
          TextSpan(
            text: 'Gizlilik Politikası',
            style: TextStyle(color: BrandColors.primary),
          ),
          TextSpan(text: 'nı kabul etmiş olursun.'),
        ],
      ),
    );
  }
}

class _Step2 extends StatelessWidget {
  const _Step2({
    required this.controller,
    required this.email,
    required this.passwordVisible,
    required this.error,
    required this.onChanged,
    required this.onTogglePasswordVisible,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String email;
  final bool passwordVisible;
  final String? error;
  final ValueChanged<String> onChanged;
  final VoidCallback onTogglePasswordVisible;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final pwd = controller.text;
    final strength = _passwordStrength(pwd);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'Şifre oluştur',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'AwaTV bulut senkronizasyonu için bu e-posta ve şifreyi kullanacaksın.',
          style: TextStyle(
            color: Color(0x80FFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 20 / 13,
          ),
        ),
        const SizedBox(height: 16),
        StreasInput(
          controller: controller,
          placeholder: 'Şifre oluştur',
          obscureText: !passwordVisible,
          autofocus: true,
          error: error != null,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmit(),
          textInputAction: TextInputAction.next,
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
        if (pwd.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _StrengthMeter(strength: strength),
        ],
        const SizedBox(height: 12),
        const Text(
          'En az 6 karakter (büyük/küçük harf duyarlı). En az 2 farklı türden karakter '
          'kullan: harf, rakam, özel karakter.',
          style: TextStyle(
            color: Color(0x66FFFFFF),
            fontSize: 11,
            fontWeight: FontWeight.w400,
            height: 17 / 11,
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            error!,
            style: const TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _EmailRecap(email: email),
        const SizedBox(height: 16),
        GradientCta(label: 'KAYIT OL', onPressed: onSubmit),
      ],
    );
  }
}

/// 4-segment strength meter — same algorithm as Streas `passwordStrength`
/// but ported to Dart. Public for testability.
int _passwordStrength(String pwd) {
  var score = 0;
  if (pwd.length >= 6) score++;
  if (pwd.length >= 10) score++;
  if (pwd.contains(RegExp('[A-Z]'))) score++;
  if (pwd.contains(RegExp('[0-9]'))) score++;
  if (pwd.contains(RegExp('[^A-Za-z0-9]'))) score++;
  if (score > 4) score = 4;
  return score;
}

const List<Color> _kStrengthColors = <Color>[
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFEAB308),
  Color(0xFF22C55E),
  Color(0xFF22C55E),
];

const List<String> _kStrengthLabels = <String>[
  '',
  'Zayıf',
  'Orta',
  'İyi',
  'Güçlü',
  'Güçlü',
];

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});

  final int strength;

  @override
  Widget build(BuildContext context) {
    final color = _kStrengthColors[strength];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Row(
            children: List<Widget>.generate(4, (int i) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
                  height: 3,
                  decoration: BoxDecoration(
                    color: strength >= i + 1
                        ? color
                        : const Color(0x1AFFFFFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 50,
          child: Text(
            _kStrengthLabels[strength],
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
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
        const SizedBox(height: 3),
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

class _Step3 extends StatelessWidget {
  const _Step3({
    required this.controller,
    required this.email,
    required this.loading,
    required this.error,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String email;
  final bool loading;
  final String? error;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'Görünen adın',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Profilinde ve paylaştığın listelerde görünecek isim. Sonradan Hesap '
          'ekranından değiştirebilirsin.',
          style: TextStyle(
            color: Color(0x80FFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 20 / 13,
          ),
        ),
        const SizedBox(height: 16),
        StreasInput(
          controller: controller,
          placeholder: 'Görünen ad',
          keyboardType: TextInputType.name,
          autofocus: true,
          error: error != null,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmit(),
          textInputAction: TextInputAction.done,
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            error!,
            style: const TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _EmailRecap(email: email),
        const SizedBox(height: 16),
        GradientCta(label: 'ONAYLA', loading: loading, onPressed: onSubmit),
      ],
    );
  }
}
