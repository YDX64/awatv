import 'dart:async';

import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

part 'auth_controller.g.dart';

/// Bridges Supabase's `GoTrueClient` auth-change stream into Riverpod.
///
/// When [Env.hasSupabase] is false (the common case for unconfigured
/// dev builds) the controller short-circuits: it emits [AuthGuest]
/// permanently and every mutating call throws
/// [AuthBackendNotConfiguredException]. The login screen detects the
/// flag and switches to a static "cloud sync isn't set up" panel
/// instead of a useless email field.
///
/// `keepAlive` because the app shell, settings row, premium gate, and
/// router redirects all consume this. Re-running `build` per-route
/// would lose the in-flight session.
@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
  StreamSubscription<supa.AuthState>? _sub;

  @override
  Stream<AuthState> build() {
    if (!Env.hasSupabase) {
      // No backend → guest forever. We still emit through a stream so
      // the screens that watch this provider observe the same async
      // shape regardless of build configuration.
      return Stream<AuthState>.value(const AuthGuest());
    }

    final controller = StreamController<AuthState>(sync: false);

    // Cleanup on provider disposal. AsyncValue listeners survive route
    // changes thanks to keepAlive, but if the provider is ever
    // invalidated we must close the supabase subscription too.
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
      controller.close();
    });

    // Seed with whatever the SDK already knows, so the login screen
    // doesn't flash "loading" when the user is already signed in.
    final initialSession = _safeCurrentSession();
    controller.add(_fromSession(initialSession));

    try {
      _sub = supa.Supabase.instance.client.auth.onAuthStateChange.listen(
        (supa.AuthState event) {
          // Map Supabase's event into our internal state. Errors during
          // a signIn/refresh are surfaced through `AuthError` so the
          // login screen can show them inline.
          controller.add(_fromSession(event.session));
        },
        onError: (Object error, StackTrace _) {
          controller.add(AuthError(error.toString()));
        },
      );
    } on Object catch (e) {
      // Supabase init must have failed earlier; degrade to guest.
      controller.add(const AuthGuest());
      if (kDebugMode) debugPrint('AuthController: $e');
    }

    return controller.stream;
  }

  /// Send a one-time magic link to [email]. The user clicks the link
  /// in their inbox, lands back on `/auth/callback`, and the listener
  /// in [build] picks up the new session.
  ///
  /// Throws [AuthBackendNotConfiguredException] when the build was not
  /// compiled with Supabase env vars, and [supa.AuthException] for
  /// upstream failures.
  Future<void> sendMagicLink(String email) async {
    if (!Env.hasSupabase) {
      throw const AuthBackendNotConfiguredException();
    }
    final trimmed = email.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      throw const supa.AuthException('Please enter a valid email address.');
    }

    final redirect = _redirectUri();
    await supa.Supabase.instance.client.auth.signInWithOtp(
      email: trimmed,
      emailRedirectTo: redirect,
      shouldCreateUser: true,
    );
  }

  /// Sign in with email + password. Faster than magic link for the
  /// initial private-beta period where every user has a hand-provisioned
  /// account. The login screen falls back to this when the user picks
  /// "Sign in with password" instead of "Send magic link".
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (!Env.hasSupabase) {
      throw const AuthBackendNotConfiguredException();
    }
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw const AuthBackendNotConfiguredException('Email is required');
    }
    if (password.isEmpty) {
      throw const AuthBackendNotConfiguredException('Password is required');
    }
    await supa.Supabase.instance.client.auth.signInWithPassword(
      email: trimmed,
      password: password,
    );
  }

  /// Sign the current user out. Idempotent — calling while already
  /// guest is a no-op so the settings screen doesn't have to branch
  /// on state before showing the action.
  Future<void> signOut() async {
    if (!Env.hasSupabase) return;
    try {
      await supa.Supabase.instance.client.auth.signOut();
    } on supa.AuthException {
      // Local sign-out still happens via the listener.
      rethrow;
    }
  }

  /// Update the user's profile display name. Stored on the Supabase
  /// user_metadata column — schema-light, no extra migrations needed.
  Future<void> updateDisplayName(String name) async {
    if (!Env.hasSupabase) {
      throw const AuthBackendNotConfiguredException();
    }
    final trimmed = name.trim();
    await supa.Supabase.instance.client.auth.updateUser(
      supa.UserAttributes(
        data: <String, dynamic>{'display_name': trimmed},
      ),
    );
  }

  /// Manually exchange a `?code=...` URL for a session. Called from
  /// the magic-link callback screen on web — on mobile the deep-link
  /// handler in supabase_flutter does this automatically.
  Future<supa.AuthSessionUrlResponse> exchangeCodeForSession(String code) async {
    if (!Env.hasSupabase) {
      throw const AuthBackendNotConfiguredException();
    }
    return supa.Supabase.instance.client.auth.exchangeCodeForSession(code);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Best-effort read of the live session. Wrapped because the SDK
  /// will throw if `Supabase.initialize` was never called — we want
  /// to swallow that and emit guest instead.
  supa.Session? _safeCurrentSession() {
    try {
      return supa.Supabase.instance.client.auth.currentSession;
    } on Object {
      return null;
    }
  }

  AuthState _fromSession(supa.Session? session) {
    if (session == null) return const AuthGuest();
    final user = session.user;
    final email = user.email ?? '';
    if (email.isEmpty) return const AuthGuest();
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final raw = meta['display_name'];
    final displayName = raw is String && raw.trim().isNotEmpty
        ? raw.trim()
        : null;
    return AuthSignedIn(
      userId: user.id,
      email: email,
      displayName: displayName,
    );
  }

  /// Where the magic-link should redirect after the user clicks it.
  ///
  /// On web we want them back on the SPA at `/auth/callback`. On
  /// mobile/desktop we hand the supabase deep-link scheme so the OS
  /// hands the URL straight back into the app.
  String? _redirectUri() {
    if (kIsWeb) {
      // Uri.base on web is the live page URL — perfect for building
      // an absolute redirect that survives custom domains.
      final origin = Uri.base.replace(
        path: '/auth/callback',
        query: '',
        fragment: '',
      );
      return origin.toString();
    }
    // Native deep-link — registered in Info.plist / AndroidManifest
    // by the supabase_flutter setup. Falling back to null lets the
    // SDK use its built-in default scheme.
    return 'io.supabase.awatv://login-callback';
  }
}

/// Convenience selector — true while we know the user is signed in.
/// Screens that don't care about the email/displayName payload can
/// watch this instead of pattern-matching the full state.
@Riverpod(keepAlive: true)
bool isSignedIn(Ref ref) {
  final state = ref.watch(authControllerProvider).valueOrNull;
  return state is AuthSignedIn;
}
