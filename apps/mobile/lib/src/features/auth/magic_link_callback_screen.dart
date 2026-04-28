import 'dart:async';

import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// Receives `?code=…` redirects from the magic-link email on web.
///
/// On mobile / desktop the supabase_flutter deep-link handler does the
/// exchange automatically — this screen still renders briefly to give
/// the user feedback while we wait for the auth listener to flip the
/// state to [AuthSignedIn].
class MagicLinkCallbackScreen extends ConsumerStatefulWidget {
  const MagicLinkCallbackScreen({this.next, this.code, this.error, super.key});

  final String? next;
  final String? code;

  /// Supabase will sometimes redirect with `?error_description=` instead
  /// of a code (link expired, link reused, etc.).
  final String? error;

  @override
  ConsumerState<MagicLinkCallbackScreen> createState() =>
      _MagicLinkCallbackScreenState();
}

class _MagicLinkCallbackScreenState
    extends ConsumerState<MagicLinkCallbackScreen> {
  String? _error;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _error = widget.error;
    // Kick off the exchange asynchronously so the first frame can paint.
    scheduleMicrotask(_consumeCode);
  }

  Future<void> _consumeCode() async {
    final code = widget.code;
    if (code == null || code.isEmpty) {
      // No code AND no error — likely a stale tab. Treat as soft-error.
      if (_error == null && !_resolved) {
        setState(() {
          _error = 'No magic-link code in the URL.';
        });
      }
      return;
    }

    try {
      await ref.read(authControllerProvider.notifier).exchangeCodeForSession(code);
      // Listener in AuthController will emit AuthSignedIn — our listen
      // hook below will then route forward.
    } on AuthBackendNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Cloud sync is not configured.';
      });
    } on supa.AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Couldn\'t finish signing in.\n$e';
      });
    }
  }

  void _routeForward(AuthSignedIn signedIn) {
    if (_resolved) return;
    _resolved = true;
    final next = widget.next;
    final fallback = (next == null || next.isEmpty || next.startsWith('/login'))
        ? '/home'
        : next;
    // If the user juggles 2+ profiles on this device, route them
    // through the picker before any per-profile screen renders.
    String dest = fallback;
    try {
      final list = ref.read(profileControllerProvider).currentList();
      if (list.length >= 2) dest = '/profiles';
    } on Object {
      // Storage hiccup — fall back to whatever we computed above.
    }
    // Tiny delay so the "Welcome back" text gets to render briefly.
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      context.go(dest);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Listen so we react the moment the auth listener emits.
    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (_, next) {
      final value = next.valueOrNull;
      if (value is AuthSignedIn) {
        _routeForward(value);
      }
    });

    final auth = ref.watch(authControllerProvider).valueOrNull;
    final signedIn = auth is AuthSignedIn ? auth : null;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_error != null)
                  _ErrorPanel(error: _error!)
                else if (signedIn != null)
                  _WelcomePanel(signedIn: signedIn)
                else
                  Column(
                    children: <Widget>[
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: DesignTokens.spaceL),
                      Text(
                        'Signing you in…',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.signedIn});

  final AuthSignedIn signedIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = signedIn.displayName ?? signedIn.email.split('@').first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: BrandColors.brandGradient,
          ),
          child: const Icon(
            Icons.check_circle_outline_rounded,
            size: 52,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceL),
        Text(
          'Welcome back, $name',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: DesignTokens.spaceS),
        Text(
          signedIn.email,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Icon(
          Icons.error_outline_rounded,
          size: 48,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: DesignTokens.spaceM),
        Text(
          'Sign-in didn\'t complete',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: DesignTokens.spaceS),
        Text(
          error,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceL),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Try again'),
        ),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Continue without signing in'),
        ),
      ],
    );
  }
}
