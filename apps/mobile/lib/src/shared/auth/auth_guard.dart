import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// go_router redirect predicate that bounces unauthenticated users to
/// `/login` while preserving the originally-requested path in `?next=`.
///
/// Returns `null` (= "stay") when the auth state is signed-in. Anything
/// else — guest, loading, error — gets redirected. Loading bouncing the
/// route once on first paint is acceptable because the seed value of
/// the controller already reflects whatever Supabase had stored, so
/// returning users land directly on the protected screen.
///
/// The [ref] is the `Ref` from the enclosing `@Riverpod GoRouter
/// appRouter` provider — go_router redirect callbacks don't have
/// access to a `WidgetRef`, so we close over the provider's `Ref`.
String? authGuard(GoRouterState state, Ref ref) {
  final auth = ref.read(authControllerProvider).valueOrNull;
  if (auth is AuthSignedIn) return null;

  final next = Uri.encodeComponent(state.matchedLocation);
  return '/login?next=$next';
}
