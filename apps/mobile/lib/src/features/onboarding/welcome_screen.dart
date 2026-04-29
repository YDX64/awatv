import 'package:awatv_mobile/src/features/onboarding/wizard_screen.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// First-run welcome — now a thin wrapper around the multi-step
/// wizard. We keep this widget so the legacy `/onboarding` route still
/// resolves; the moment the wrapper mounts it either pushes the
/// wizard (if not yet completed) or jumps to /home.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    // Defer to post-frame so we don't navigate during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  void _decide() {
    if (_redirected) return;
    _redirected = true;
    if (!mounted) return;
    final storage = ref.read(awatvStorageProvider);
    if (isOnboardingCompleted(storage)) {
      // Already onboarded — fall through to the home shell. The
      // playlist redirect in the router handles "no playlist" cases.
      context.go('/home');
      return;
    }
    context.go('/onboarding/wizard');
  }

  @override
  Widget build(BuildContext context) {
    // Render a minimal placeholder while the redirect lands. The
    // wizard takes over almost immediately so users typically never
    // see this body.
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: DesignTokens.spaceL),
              Text(
                'AWAtv hazirlaniyor...',
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
