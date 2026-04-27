/// Authentication state machine.
///
/// `AuthGuest` is the *default* state for the AWAtv app — most users
/// will never sign in. The whole feature is opt-in: signed-in users
/// get cross-device cloud sync; guests stay on-device only.
///
/// Sealed so screens can pattern-match on the state without writing
/// fall-through branches that mask new variants.
sealed class AuthState {
  const AuthState();
}

/// Boot transient — controller hasn't yet observed a session decision.
final class AuthLoading extends AuthState {
  const AuthLoading();
}

/// Not signed in — using AWAtv as a local-only guest. This is the
/// default for first-run, signed-out, and "Supabase not configured"
/// builds.
final class AuthGuest extends AuthState {
  const AuthGuest();
}

/// Signed in with a confirmed email. [displayName] is optional and may
/// be edited from the account screen; [email] is always present
/// because Supabase magic-link only authenticates email-bearing users.
final class AuthSignedIn extends AuthState {
  const AuthSignedIn({
    required this.userId,
    required this.email,
    this.displayName,
  });

  final String userId;
  final String email;
  final String? displayName;

  AuthSignedIn copyWith({String? displayName}) {
    return AuthSignedIn(
      userId: userId,
      email: email,
      displayName: displayName ?? this.displayName,
    );
  }
}

/// Recoverable auth failure (rate-limit, network drop, server error).
/// The login screen renders [message] inline; the controller resets to
/// the previous state on retry.
final class AuthError extends AuthState {
  const AuthError(this.message);

  final String message;
}

/// Thrown from `AuthController.sendMagicLink` / `signOut` /
/// `updateDisplayName` when the build doesn't have Supabase configured.
/// The login screen catches this to flip into "backend not configured"
/// mode rather than showing a misleading network error.
class AuthBackendNotConfiguredException implements Exception {
  const AuthBackendNotConfiguredException([this.message]);

  final String? message;

  @override
  String toString() =>
      'AuthBackendNotConfiguredException: ${message ?? 'Supabase not configured.'}';
}
