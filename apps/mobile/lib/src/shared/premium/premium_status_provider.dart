import 'dart:async';
import 'dart:convert';

import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

part 'premium_status_provider.g.dart';

/// Hive `prefs` box key — used as an offline read-cache only. The
/// Supabase `subscriptions` row is the only writable source of truth.
const String _kPrefsKey = 'premium:tier';

/// Single-row notifier holding the user's active subscription state.
///
/// **Anti-tamper architecture (v0.5.8+):** the local Hive cache is
/// **never** authoritative. On every signed-in boot the notifier
/// queries `public.subscriptions` directly via Supabase. RLS lets
/// users SELECT their own row but prevents INSERT / UPDATE / DELETE
/// — only the service-role-keyed `revenuecat-webhook` Edge Function
/// can mutate it. A LuckyPatcher-style device-side write to Hive
/// flips the cache to "premium" but the next boot pulls from
/// Supabase and overwrites the lie.
///
/// Boot-time decision tree:
///   1. Read Hive cache for the immediate render (avoids a free→
///      premium frame flicker for already-paid users).
///   2. If signed in, fetch subscriptions row.
///   3. Compare with cache; persist whichever is newer / authoritative.
///   4. Server response always wins on conflict.
///   5. If signed out, force `FreeTier()` regardless of cache.
@Riverpod(keepAlive: true)
class PremiumStatus extends _$PremiumStatus {
  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;

  @override
  PremiumTier build() {
    // Re-fetch from Supabase whenever auth flips. Keep cache as a
    // first-frame paint hint; truth is server-side.
    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (prev, next) {
      final s = next.valueOrNull;
      if (s is AuthSignedIn) {
        unawaited(_refreshFromServer());
        _attachRealtime(s.userId);
      } else {
        // Signed out → revoke cache, demote to free.
        _detachRealtime();
        unawaited(_persist(const FreeTier()));
        state = const FreeTier();
      }
    });

    ref.onDispose(() => _detachRealtime());

    final initial = _readPersisted();
    // If the cache says "premium" but the entitlement window has
    // elapsed, demote on boot before the UI sees a stale tier.
    if (initial is PremiumTierActive &&
        initial.isExpired(DateTime.now().toUtc())) {
      _persist(const FreeTier());
      // Defer the server check; if the user is signed in, the auth
      // listener above will refresh.
      return const FreeTier();
    }

    // Kick a server check eagerly if we're already signed in at build
    // time (Supabase SDK seeds the session synchronously on boot).
    final session = _safeCurrentSession();
    if (session != null) {
      unawaited(_refreshFromServer());
      _attachRealtime(session.user.id);
    }

    return initial;
  }

  // ---------------------------------------------------------------------
  // Server-side authoritative read
  // ---------------------------------------------------------------------

  /// Pull the live subscription row from Supabase. The RLS policy
  /// `subscriptions_select_own` ensures we only see our own row.
  ///
  /// Returns silently on network errors so a flaky uplink doesn't kick
  /// a paying user back to free tier; the cache stays in place. The
  /// realtime listener will catch the next valid update.
  Future<void> _refreshFromServer() async {
    try {
      final client = supa.Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        await _persist(const FreeTier());
        if (state != const FreeTier()) state = const FreeTier();
        return;
      }
      final row = await client
          .from('subscriptions')
          .select(
            'plan, status, expires_at, will_renew',
          )
          .eq('user_id', user.id)
          .maybeSingle();

      final tier = _tierFromRow(row);
      if (tier != state) {
        state = tier;
        await _persist(tier);
      }
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[premium] refresh failed: $e');
    }
  }

  /// Subscribe to realtime updates of the `subscriptions` row so a
  /// purchase / cancellation reflects in <1s without a poll. Filtered
  /// to the current user's row only via RLS.
  void _attachRealtime(String userId) {
    _detachRealtime();
    try {
      final stream = supa.Supabase.instance.client
          .from('subscriptions')
          .stream(primaryKey: <String>['user_id'])
          .eq('user_id', userId);
      _realtimeSub = stream.listen((rows) {
        if (rows.isEmpty) {
          if (state != const FreeTier()) {
            state = const FreeTier();
            unawaited(_persist(const FreeTier()));
          }
          return;
        }
        final tier = _tierFromRow(rows.first);
        if (tier != state) {
          state = tier;
          unawaited(_persist(tier));
        }
      });
    } on Object {
      // Realtime not available → fall through to periodic refresh.
    }
  }

  void _detachRealtime() {
    _realtimeSub?.cancel();
    _realtimeSub = null;
  }

  PremiumTier _tierFromRow(Map<String, dynamic>? row) {
    if (row == null) return const FreeTier();
    final status = row['status'] as String? ?? 'expired';
    if (status == 'expired' || status == 'cancelled') {
      // cancelled-but-still-in-window also routes here once expires_at
      // ≤ now per the webhook's mapStatus logic.
      final expRaw = row['expires_at'] as String?;
      final exp = expRaw != null ? DateTime.tryParse(expRaw) : null;
      if (exp == null || exp.isBefore(DateTime.now().toUtc())) {
        return const FreeTier();
      }
      // Cancelled but not yet expired — still entitled.
    }
    final planStr = row['plan'] as String? ?? 'monthly';
    final plan = switch (planStr) {
      'yearly' => PremiumPlan.yearly,
      'lifetime' => PremiumPlan.lifetime,
      _ => PremiumPlan.monthly,
    };
    final expRaw = row['expires_at'] as String?;
    final willRenew = row['will_renew'] as bool? ?? false;
    return PremiumTierActive(
      plan: plan,
      expiresAt: expRaw != null ? DateTime.tryParse(expRaw) : null,
      willRenew: willRenew,
    );
  }

  supa.Session? _safeCurrentSession() {
    try {
      return supa.Supabase.instance.client.auth.currentSession;
    } on Object {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Public API — same surface as before so callers don't break
  // ---------------------------------------------------------------------

  /// Debug-only entry-point used by the paywall in dev to skip the IAP
  /// flow. Production builds (`!kDebugMode`) refuse the call so it
  /// can't be used to bypass the server-side gate.
  ///
  /// Real activation lands via the RevenueCat → Supabase webhook → realtime
  /// subscription stream chain.
  Future<void> simulateActivate(PremiumPlan plan) async {
    if (!kDebugMode) {
      // Refuse the call entirely in release builds. The notifier still
      // holds whatever state Supabase last said — caller's UX should
      // route to the real RevenueCat purchase flow.
      if (kDebugMode) debugPrint('[premium] simulateActivate ignored in release');
      return;
    }
    final now = DateTime.now().toUtc();
    final next = switch (plan) {
      PremiumPlan.monthly => PremiumTierActive(
          plan: plan,
          expiresAt: now.add(const Duration(days: 30)),
          willRenew: true,
        ),
      PremiumPlan.yearly => PremiumTierActive(
          plan: plan,
          expiresAt: now.add(const Duration(days: 365)),
          willRenew: true,
        ),
      PremiumPlan.lifetime => PremiumTierActive(
          plan: plan,
          expiresAt: null,
          willRenew: false,
        ),
    };
    state = next;
    await _persist(next);
  }

  /// Returns the user to the free tier locally. Server-side state is
  /// untouched — RC's CANCELLATION webhook is what actually flips the
  /// `subscriptions.status` column. This method is for the auth-signout
  /// hook that wipes local state.
  Future<void> signOut() async {
    state = const FreeTier();
    await _persist(const FreeTier());
  }

  /// Re-evaluates expiry + re-fetches from server. Called when the
  /// app foregrounds.
  Future<void> reconcile() async {
    await _refreshFromServer();
    final current = state;
    if (current is PremiumTierActive &&
        current.isExpired(DateTime.now().toUtc())) {
      state = const FreeTier();
      await _persist(const FreeTier());
    }
  }

  // ---------------------------------------------------------------------
  // Persistence helpers — Hive is offline-cache only, never authoritative
  // ---------------------------------------------------------------------

  PremiumTier _readPersisted() {
    final box = ref.read(awatvStorageProvider).prefsBox;
    final raw = box.get(_kPrefsKey);
    if (raw is! String || raw.isEmpty) return const FreeTier();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _decode(json);
    } on Object {
      return const FreeTier();
    }
  }

  Future<void> _persist(PremiumTier tier) async {
    final box = ref.read(awatvStorageProvider).prefsBox;
    await box.put(_kPrefsKey, jsonEncode(_encode(tier)));
  }

  static Map<String, dynamic> _encode(PremiumTier tier) => switch (tier) {
        FreeTier() => <String, dynamic>{'tier': 'free'},
        PremiumTierActive(
          :final plan,
          :final expiresAt,
          :final willRenew,
        ) =>
          <String, dynamic>{
            'tier': 'premium',
            'plan': plan.name,
            'expiresAt': expiresAt?.toIso8601String(),
            'willRenew': willRenew,
          },
      };

  static PremiumTier _decode(Map<String, dynamic> json) {
    final kind = json['tier'] as String?;
    if (kind != 'premium') return const FreeTier();
    final planName = json['plan'] as String?;
    final plan = PremiumPlan.values.firstWhere(
      (p) => p.name == planName,
      orElse: () => PremiumPlan.monthly,
    );
    final expires = json['expiresAt'];
    final willRenew = json['willRenew'];
    return PremiumTierActive(
      plan: plan,
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
      willRenew: willRenew is bool && willRenew,
    );
  }
}
