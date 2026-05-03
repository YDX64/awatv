import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// AWAtv welcome screen — Streas-port.
///
/// Renders a full-bleed mosaic backdrop, the "AwaTV" wordmark, and a
/// stack of CTAs that adapt to whether Supabase is configured for this
/// build. The animation sequence (logo spring + fade, buttons fade with
/// 200ms delay) mirrors `app/welcome.tsx` from the React Native source
/// at `/tmp/Streas/artifacts/iptv-app/`.
///
/// Behavior:
///  * Configured build: LOGIN (cherry gradient) + CREATE AN ACCOUNT
///    (outlined) + UPLOAD YOUR PLAYLIST (text+icon) + Continue as
///    Guest (ghost link).
///  * Unconfigured build: info banner + BROWSE AS GUEST cherry CTA +
///    UPLOAD YOUR PLAYLIST.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final AnimationController _buttonsController;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    // Spring-ish curve approximation of RN's tension:50 friction:8 spring.
    _logoScale = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOut),
    );
    _buttonsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _runEntrance();
  }

  Future<void> _runEntrance() async {
    await _logoController.forward();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (mounted) await _buttonsController.forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _buttonsController.dispose();
    super.dispose();
  }

  /// Streas opens a native document picker for `.m3u` / `.m3u8` files;
  /// AWAtv routes to the onboarding wizard instead — that screen already
  /// supports M3U URL + Xtream + Stalker import flows and handles
  /// validation centrally. The label keeps Streas' "upload playlist"
  /// language.
  void _uploadPlaylist() {
    context.push('/onboarding/wizard');
  }

  void _continueAsGuest() {
    // Flutter does not have an explicit "guest" call — the auth
    // controller already emits AuthGuest by default. Just bounce to the
    // appropriate post-login destination.
    context.go(_postLoginDestination());
  }

  String _postLoginDestination() => resolvePostLoginDestination(ref);

  @override
  Widget build(BuildContext context) {
    final hasBackend = Env.hasSupabase;
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final tileHeight = size.height / 4;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: <Widget>[
          // ─── Mosaic backdrop ─────────────────────────────────────
          Positioned.fill(
            child: _MosaicBackdrop(tileHeight: tileHeight),
          ),
          // ─── Vertical scrim ──────────────────────────────────────
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0x4D050912), // 30% near-black
                    Color(0xB3050912), // 70%
                    Color(0xF2050912), // 95%
                    Color(0xFF0A0A0A),
                  ],
                  stops: <double>[0, 0.45, 0.8, 1],
                ),
              ),
            ),
          ),
          // ─── Content ─────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  const SizedBox(height: 20),
                  // ─── Logo block ────────────────────────────────
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (BuildContext _, Widget? child) {
                      return Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: child,
                        ),
                      );
                    },
                    child: const _LogoBlock(),
                  ),
                  const Spacer(),
                  // ─── Buttons ──────────────────────────────────
                  AnimatedBuilder(
                    animation: _buttonsController,
                    builder: (BuildContext _, Widget? child) {
                      return Opacity(
                        opacity: _buttonsController.value,
                        child: child,
                      );
                    },
                    child: _ButtonStack(
                      hasBackend: hasBackend,
                      onLogin: () => context.push('/login'),
                      onSignup: () => context.push('/signup'),
                      onGuest: _continueAsGuest,
                      onUpload: _uploadPlaylist,
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 12-tile (4 row × 3 col) mosaic backdrop. Tile colors cycle through
/// `#141414`, `#0d1525`, `#0a1020` to match the Streas RN reference.
class _MosaicBackdrop extends StatelessWidget {
  const _MosaicBackdrop({required this.tileHeight});

  final double tileHeight;

  static const List<Color> _palette = <Color>[
    Color(0xFF141414),
    Color(0xFF0D1525),
    Color(0xFF0A1020),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(4, (int row) {
        return Row(
          children: List<Widget>.generate(3, (int col) {
            final index = row * 3 + col;
            return Expanded(
              child: Container(
                height: tileHeight,
                color: _palette[index % _palette.length],
              ),
            );
          }),
        );
      }),
    );
  }
}

class _LogoBlock extends StatelessWidget {
  const _LogoBlock();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: <Widget>[
          // Cherry square logo mark.
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: BrandColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: const Text(
              'AW',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // "AwaTV" wordmark.
          RichText(
            text: const TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: 'Awa',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    height: 1.05,
                  ),
                ),
                TextSpan(
                  text: 'TV',
                  style: TextStyle(
                    color: BrandColors.primary,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Eğlence Merkeziniz',
            style: TextStyle(
              color: Color(0x80FFFFFF),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonStack extends StatelessWidget {
  const _ButtonStack({
    required this.hasBackend,
    required this.onLogin,
    required this.onSignup,
    required this.onGuest,
    required this.onUpload,
  });

  final bool hasBackend;
  final VoidCallback onLogin;
  final VoidCallback onSignup;
  final VoidCallback onGuest;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (hasBackend) {
      children
        ..add(GradientCta(label: 'GİRİŞ YAP', onPressed: onLogin))
        ..add(const SizedBox(height: 12))
        ..add(_OutlinedCta(label: 'HESAP OLUŞTUR', onPressed: onSignup));
    } else {
      children
        ..add(const _UnconfiguredBanner())
        ..add(const SizedBox(height: 12))
        ..add(GradientCta(label: 'MİSAFİR OLARAK BAŞLA', onPressed: onGuest));
    }
    children
      ..add(const SizedBox(height: 8))
      ..add(_UploadCta(onPressed: onUpload));
    if (hasBackend) {
      children
        ..add(const SizedBox(height: 4))
        ..add(_GhostLink(label: 'Misafir devam et', onPressed: onGuest));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Cherry-gradient CTA button (`#9F1239` → `#E11D48` left-to-right).
/// Reused from welcome / login / signup / profile-save screens.
class GradientCta extends StatelessWidget {
  const GradientCta({
    required this.label,
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null || loading ? 0.7 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[Color(0xFF9F1239), Color(0xFFE11D48)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: InkWell(
            onTap: loading ? null : onPressed,
            child: SizedBox(
              height: 52,
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlinedCta extends StatelessWidget {
  const _OutlinedCta({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x40FFFFFF)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xD9FFFFFF),
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadCta extends StatelessWidget {
  const _UploadCta({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.upload_rounded,
              size: 14,
              color: Color(0x99FFFFFF),
            ),
            SizedBox(width: 8),
            Text(
              'OYNATMA LİSTESİ YÜKLE',
              style: TextStyle(
                color: Color(0x8CFFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostLink extends StatelessWidget {
  const _GhostLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0x66FFFFFF),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _UnconfiguredBanner extends StatelessWidget {
  const _UnconfiguredBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1F3B82F6),
        border: Border.all(color: const Color(0x4D3B82F6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: BrandColors.primary,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Bulut senkronizasyonu ve giriş için Ayarlar'dan Supabase "
              'bilgilerini ekleyin.',
              style: TextStyle(
                color: Color(0x99FFFFFF),
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

// Re-export pattern: shared widgets exposed to other auth screens. We
// intentionally don't pull these into `awatv_ui` yet — they're auth-flow
// specific and the spec puts them under `lib/src/features/auth/widgets/`
// in a follow-up. For now we use `package:` imports between screens.
class StreasInput extends StatelessWidget {
  const StreasInput({
    required this.controller,
    required this.placeholder,
    this.keyboardType,
    this.obscureText = false,
    this.locked = false,
    this.error = false,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.suffix,
    this.textInputAction,
    super.key,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool locked;
  final bool error;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final Widget? suffix;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final borderColor = error
        ? const Color(0xFFEF4444)
        : locked
            ? Colors.transparent
            : const Color(0x33FFFFFF);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x12FFFFFF),
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              enabled: !locked,
              keyboardType: keyboardType,
              obscureText: obscureText,
              autocorrect: false,
              textInputAction: textInputAction,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: InputBorder.none,
                hintText: placeholder,
                hintStyle: const TextStyle(
                  color: Color(0x59FFFFFF),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          if (suffix != null) suffix!,
        ],
      ),
    );
  }
}

/// Helper used by login/signup screens to bounce to the right
/// post-auth destination.
String resolvePostLoginDestination(WidgetRef ref) {
  try {
    final list = ref.read(profileControllerProvider).currentList();
    if (list.length >= 2) return '/profiles';
  } on Object {
    // fall through
  }
  return '/home';
}

/// Convenience predicate exposed for the `go_router` redirect rule
/// described in the spec § 10. Imported by `auth_guard.dart` so the
/// router can lock `/account` etc. behind a non-loading auth state
/// without depending on the welcome screen widget tree itself.
bool isWelcomeAuthorityState(AuthState state) =>
    state is AuthGuest || state is AuthSignedIn;
