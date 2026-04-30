import 'dart:async';
import 'dart:developer' as developer;

import 'package:awatv_mobile/src/shared/remote_config/rc_snapshot.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_remote_config.g.dart';

/// Live Remote Config snapshot.
///
/// Boot sequence:
///   1. Emit the [RcSnapshot.fallback] immediately so the UI doesn't
///      show empty placeholders during the fetch.
///   2. Try to initialise Firebase + Remote Config in the background.
///   3. On success, replace the state with the live snapshot.
///
/// All steps are wrapped in try/catch — a missing google-services file
/// or a flaky network must never block the app.
///
/// Because the provider is `keepAlive`, every consumer (paywall, home
/// shell, cast button) sees the same snapshot for the lifetime of the
/// app and rebuilds atomically when RC fetches a new one.
@Riverpod(keepAlive: true)
class AppRemoteConfig extends _$AppRemoteConfig {
  @override
  RcSnapshot build() {
    // Kick off the bootstrap but don't block the build — the UI gets
    // the fallback immediately and re-renders as soon as RC returns.
    unawaited(_bootstrap());
    return const RcSnapshot.fallback();
  }

  Future<void> _bootstrap() async {
    if (kIsWeb) {
      // We don't bundle the Firebase JS SDK; treat web as a permanent
      // fallback regime. Marketing copy + flags are baked in.
      return;
    }

    // Step 1 — Firebase init. If this throws (no GoogleService config
    // on disk, native plugin not registered) we silently keep the
    // fallback. The observability layer logs the same root cause.
    try {
      // `initializeApp` is idempotent — a second call after the
      // observability bootstrap already ran is a no-op that returns
      // the cached default app.
      await Firebase.initializeApp();
    } on Object catch (e) {
      developer.log(
        'Remote Config skipped: Firebase init failed.',
        name: 'awatv.remote_config',
        error: e,
      );
      return;
    }

    final rc = FirebaseRemoteConfig.instance;

    // Step 2 — sensible defaults so a fresh user with no network sees
    // exactly the same content as one mid-fetch.
    try {
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kDebugMode
              ? Duration.zero
              : const Duration(hours: 6),
        ),
      );
      await rc.setDefaults(RcKeys.defaults);
    } on Object catch (e) {
      developer.log(
        'Remote Config defaults failed.',
        name: 'awatv.remote_config',
        error: e,
      );
      // Continue — a failed defaults call is still recoverable.
    }

    // Step 3 — fetch + activate. Failures here are *very* common in
    // dev (no project, no internet, throttled) and absolutely must not
    // surface to the user.
    try {
      await rc.fetchAndActivate();
    } on Object catch (e) {
      developer.log(
        'Remote Config fetch failed; using local defaults.',
        name: 'awatv.remote_config',
        error: e,
      );
    }

    // Always read whatever values are in memory — defaults if the
    // fetch failed, live values if it succeeded.
    try {
      state = _snapshotFrom(rc);
    } on Object catch (e) {
      developer.log(
        'Remote Config read failed.',
        name: 'awatv.remote_config',
        error: e,
      );
    }
  }

  /// Force a refresh — the settings screen could expose a "Check for
  /// updates" button that calls this. Throttled to RC's
  /// `minimumFetchInterval` so a hammering user doesn't burn quota.
  Future<void> refresh() async {
    if (kIsWeb) return;
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.fetchAndActivate();
      state = _snapshotFrom(rc);
    } on Object catch (e) {
      developer.log(
        'Remote Config refresh failed.',
        name: 'awatv.remote_config',
        error: e,
      );
    }
  }

  /// Translate the Firebase Remote Config object into our typed snapshot.
  /// Pure function so we can unit-test the mapping if we add a fake RC
  /// shim later.
  RcSnapshot _snapshotFrom(FirebaseRemoteConfig rc) {
    String s(String key, String fallback) {
      try {
        final v = rc.getString(key);
        return v.isEmpty ? fallback : v;
      } on Object {
        return fallback;
      }
    }

    // Local boolean reader — positional `fallback` mirrors the
    // `s(key, fallback)` helper above so the call sites stay symmetrical.
    // ignore: avoid_positional_boolean_parameters
    bool b(String key, bool fallback) {
      try {
        return rc.getBool(key);
      } on Object {
        return fallback;
      }
    }

    int i(String key, int fallback) {
      try {
        final v = rc.getInt(key);
        return v == 0 ? fallback : v;
      } on Object {
        return fallback;
      }
    }

    return RcSnapshot(
      paywallVariant: s(RcKeys.paywallVariant, 'A'),
      priceMonthly: s(RcKeys.priceMonthly, 'EUR 3,99 / ay'),
      priceYearly: s(RcKeys.priceYearly, 'EUR 29,99 / yil'),
      priceLifetime: s(RcKeys.priceLifetime, 'EUR 69,99'),
      castEnabled: b(RcKeys.featureFlagCast, true),
      remoteControlEnabled: b(RcKeys.featureFlagRemoteControl, true),
      maintenanceMessage: s(RcKeys.maintenanceMessage, ''),
      freeTrialDays: i(RcKeys.freeTrialDays, 3),
    );
  }
}

/// Convenience read — the paywall variant string in isolation.
@Riverpod(keepAlive: true)
String paywallVariant(Ref ref) {
  return ref.watch(appRemoteConfigProvider).paywallVariant;
}

/// Convenience read — when truthy the home shell paints a maintenance
/// banner over the top of the content area.
@Riverpod(keepAlive: true)
String maintenanceMessage(Ref ref) {
  return ref.watch(appRemoteConfigProvider).maintenanceMessage;
}
