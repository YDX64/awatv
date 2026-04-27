import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// Magic-link sign-in screen.
///
/// Three render modes:
///   1. **Backend not configured** (`!Env.hasSupabase`) — yellow banner,
///      disabled email field, guest CTA highlighted.
///   2. **Form** — email entry + "Send magic link" + "Continue without
///      signing in" ghost button.
///   3. **Sent** — success card with the email address and a "Wrong
///      email?" affordance to go back to the form.
///
/// The screen is purposefully shallow: actual auth state lives in
/// [authControllerProvider] and the magic-link callback flips the
/// route as soon as a session lands.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({this.next, super.key});

  /// Where to navigate after a successful sign-in. Encoded as `?next=`
  /// in the query string by [authGuard].
  final String? next;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _LoginPhase { entering, sending, sent }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _LoginPhase _phase = _LoginPhase.entering;
  String? _error;
  String _sentTo = '';
  bool _passwordMode = true;        // Default to password — magic link is opt-in.
  bool _passwordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailController.text.trim();
    setState(() {
      _phase = _LoginPhase.sending;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).sendMagicLink(email);
      if (!mounted) return;
      setState(() {
        _phase = _LoginPhase.sent;
        _sentTo = email;
      });
    } on AuthBackendNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _LoginPhase.entering;
        _error = e.message ?? 'Cloud sync is not configured for this build.';
      });
    } on supa.AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _LoginPhase.entering;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _LoginPhase.entering;
        _error = 'Couldn\'t send the link. Please try again.\n$e';
      });
    }
  }

  Future<void> _signInWithPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailController.text.trim();
    final pw = _passwordController.text;
    setState(() {
      _phase = _LoginPhase.sending;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signInWithPassword(
            email: email,
            password: pw,
          );
      if (!mounted) return;
      // Auth state listener will route us; reset form just in case.
      setState(() => _phase = _LoginPhase.entering);
      final next = widget.next ?? '/';
      if (!next.startsWith('/login') && !next.startsWith('/auth')) {
        context.go(next);
      } else {
        context.go('/');
      }
    } on AuthBackendNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _LoginPhase.entering;
        _error = e.message ?? 'Cloud sync is not configured for this build.';
      });
    } on supa.AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _LoginPhase.entering;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _LoginPhase.entering;
        _error = 'Sign-in failed. Please check your credentials.\n$e';
      });
    }
  }

  void _continueAsGuest() {
    final next = widget.next ?? '/';
    if (next.startsWith('/login') || next.startsWith('/auth')) {
      context.go('/');
    } else {
      context.go(next);
    }
  }

  void _resetForm() {
    setState(() {
      _phase = _LoginPhase.entering;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBackend = Env.hasSupabase;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _continueAsGuest,
          tooltip: 'Skip',
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spaceL,
                DesignTokens.spaceM,
                DesignTokens.spaceL,
                DesignTokens.spaceXl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _BrandHero(),
                  const SizedBox(height: DesignTokens.spaceL),
                  Text(
                    _phase == _LoginPhase.sent
                        ? 'Check your email'
                        : 'Sign in to AWAtv',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceS),
                  Text(
                    _phase == _LoginPhase.sent
                        ? 'We sent a one-time link to $_sentTo. Tap it on this '
                            'device to finish signing in.'
                        : 'Sync your playlists across phone, TV, and desktop.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceL),
                  if (!hasBackend)
                    const _BackendNotConfiguredBanner()
                  else if (_phase == _LoginPhase.sent)
                    _SentPanel(
                      email: _sentTo,
                      onWrongEmail: _resetForm,
                    )
                  else
                    _LoginForm(
                      formKey: _formKey,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      passwordMode: _passwordMode,
                      passwordVisible: _passwordVisible,
                      enabled: _phase != _LoginPhase.sending,
                      sending: _phase == _LoginPhase.sending,
                      error: _error,
                      onSubmit: _passwordMode ? _signInWithPassword : _send,
                      onTogglePasswordMode: () => setState(() {
                        _passwordMode = !_passwordMode;
                        _error = null;
                      }),
                      onTogglePasswordVisible: () => setState(() {
                        _passwordVisible = !_passwordVisible;
                      }),
                    ),
                  const SizedBox(height: DesignTokens.spaceL),
                  TextButton.icon(
                    onPressed: _continueAsGuest,
                    icon: const Icon(Icons.no_accounts_outlined),
                    label: const Text('Continue without signing in'),
                  ),
                  const SizedBox(height: DesignTokens.spaceL),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.lock_outline, size: 16),
                      const SizedBox(width: DesignTokens.spaceS),
                      Expanded(
                        child: Text(
                          'Your playlist credentials never leave your device.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
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
      ),
    );
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: BrandColors.brandGradient,
        ),
        child: const Icon(
          Icons.live_tv_rounded,
          size: 52,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.passwordMode,
    required this.passwordVisible,
    required this.enabled,
    required this.sending,
    required this.error,
    required this.onSubmit,
    required this.onTogglePasswordMode,
    required this.onTogglePasswordVisible,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool passwordMode;
  final bool passwordVisible;
  final bool enabled;
  final bool sending;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onTogglePasswordMode;
  final VoidCallback onTogglePasswordVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            controller: emailController,
            enabled: enabled,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const <String>[AutofillHints.email],
            textInputAction: TextInputAction.send,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.alternate_email_rounded),
              border: OutlineInputBorder(),
            ),
            validator: (String? value) {
              final v = (value ?? '').trim();
              if (v.isEmpty) return 'Enter your email address.';
              if (!v.contains('@') || !v.contains('.')) {
                return 'That doesn\'t look like an email.';
              }
              return null;
            },
            onFieldSubmitted: (_) => enabled ? onSubmit() : null,
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: DesignTokens.spaceM),
            Container(
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(DesignTokens.radiusM),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: DesignTokens.spaceS),
                  Expanded(
                    child: Text(
                      error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (passwordMode) ...<Widget>[
            const SizedBox(height: DesignTokens.spaceM),
            TextFormField(
              controller: passwordController,
              enabled: enabled,
              obscureText: !passwordVisible,
              autofillHints: const <String>[AutofillHints.password],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    passwordVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                  onPressed: onTogglePasswordVisible,
                ),
                border: const OutlineInputBorder(),
              ),
              validator: (String? value) {
                if (!passwordMode) return null;
                if ((value ?? '').isEmpty) return 'Enter your password.';
                return null;
              },
              onFieldSubmitted: (_) => enabled ? onSubmit() : null,
            ),
          ],
          const SizedBox(height: DesignTokens.spaceM),
          FilledButton.icon(
            onPressed: enabled ? onSubmit : null,
            icon: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(passwordMode
                    ? Icons.login_rounded
                    : Icons.send_rounded),
            label: Text(sending
                ? (passwordMode ? 'Signing in…' : 'Sending…')
                : (passwordMode ? 'Sign in' : 'Send magic link')),
          ),
          const SizedBox(height: DesignTokens.spaceS),
          TextButton(
            onPressed: enabled ? onTogglePasswordMode : null,
            child: Text(
              passwordMode
                  ? 'Use magic link instead'
                  : 'Use password instead',
            ),
          ),
        ],
      ),
    );
  }
}

class _SentPanel extends StatelessWidget {
  const _SentPanel({
    required this.email,
    required this.onWrongEmail,
  });

  final String email;
  final VoidCallback onWrongEmail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(DesignTokens.spaceL),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(DesignTokens.radiusL),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.32),
            ),
          ),
          child: Column(
            children: <Widget>[
              Icon(
                Icons.mark_email_read_outlined,
                size: 36,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: DesignTokens.spaceS),
              Text(
                email,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: DesignTokens.spaceS),
              Text(
                'Waiting for you to tap the link…',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DesignTokens.spaceM),
        TextButton(
          onPressed: onWrongEmail,
          child: const Text('Wrong email? Start over'),
        ),
      ],
    );
  }
}

class _BackendNotConfiguredBanner extends StatelessWidget {
  const _BackendNotConfiguredBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
          const Icon(
            Icons.cloud_off_outlined,
            color: BrandColors.warning,
          ),
          const SizedBox(width: DesignTokens.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Cloud sync isn\'t configured for this build.',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: BrandColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceXs),
                Text(
                  'You can still use AWAtv on this device — your data stays here.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
