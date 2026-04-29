import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:hive_flutter/hive_flutter.dart';

/// Boot-time facade for Firebase-backed crash + analytics reporting.
///
/// AWAtv ships **privacy-first**: every collection switch defaults to
/// `false`, and the user has to opt in from `Settings → Gizlilik`. The
/// app must boot fine even when:
///
///   * `firebase_core` is wired but the Google config files
///     (`GoogleService-Info.plist` / `google-services.json`) are absent
///     — `Firebase.initializeApp` throws synchronously in that case.
///   * The user is on web (Crashlytics has only partial web support and
///     we keep the dependency mobile/desktop only).
///   * The user is on macOS / Windows / Linux desktop — Firebase native
///     bindings exist but the user might not have configured the project.
///
/// Therefore every external call is wrapped in a try/catch and a
/// `kIsWeb` short-circuit. Failures log a developer.log line and the
/// boot continues.
///
/// Usage from `main.dart` (after `Hive.initFlutter`):
/// ```dart
/// final box = Hive.box<dynamic>('prefs');
/// final optIn = box.get(observabilityOptInKey, defaultValue: false) == true;
/// unawaited(AwatvObservability.initialise(optIn: optIn));
/// ```
///
/// `unawaited` is intentional — the call must never block boot.
class AwatvObservability {
  AwatvObservability._();

  /// Hive key inside the `prefs` box that stores the user's opt-in
  /// preference. Defined here so the settings screen and the boot path
  /// reference the same string.
  static const String optInKey = 'observability.optIn';

  /// Hive box name where the opt-in flag lives. Settings opens / reads
  /// from this box — matches the rest of the prefs in the app.
  static const String prefsBoxName = 'prefs';

  static bool _initialised = false;

  /// True once `initialise` has run successfully and Firebase is alive.
  /// Settings uses this to render an "Aktif" hint vs a "Henuz baslatilmadi".
  static bool get isInitialised => _initialised;

  /// Boot Firebase + wire crash handlers. Wrapped end-to-end so a
  /// missing google-services file becomes a no-op instead of a crash.
  ///
  /// [optIn] is the latest value of the user preference. When `false` we
  /// still call `Firebase.initializeApp` (so a future opt-in flip can
  /// flush queued reports) but disable collection on every channel.
  static Future<void> initialise({required bool optIn}) async {
    if (_initialised) return;
    if (kIsWeb) {
      // Crashlytics web is partial; analytics web works but pulls a
      // separate JS SDK bootstrap we don't currently bundle. Treat web
      // as a no-op until we explicitly add the JS init step.
      developer.log(
        'Observability skipped on web (no firebase_core JS bootstrap).',
        name: 'awatv.observability',
      );
      return;
    }

    try {
      // `Firebase.initializeApp` throws synchronously if no platform
      // config is on disk (`GoogleService-Info.plist` on iOS/macOS,
      // `google-services.json` on Android). We catch and bail —
      // observability is opt-in *and* depends on the user (or
      // CI / store team) shipping a real Firebase project.
      await Firebase.initializeApp();
    } on Object catch (e, st) {
      developer.log(
        'Firebase init failed (likely missing google-services config). '
        'Crash + analytics reporting disabled for this run.',
        name: 'awatv.observability',
        error: e,
        stackTrace: st,
      );
      return;
    }

    try {
      // Crashlytics: collection respects [optIn]. Even when disabled the
      // SDK must still be initialised so a subsequent opt-in flush works
      // on the next launch.
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(optIn);

      // Capture FlutterError.onError. We always *log* to developer.log
      // so devs see the stack in DevTools, but only forward to
      // Crashlytics when the user has opted in.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (optIn) {
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        }
        if (originalOnError != null) {
          originalOnError(details);
        } else {
          FlutterError.presentError(details);
        }
      };

      // PlatformDispatcher.onError catches async errors that escape
      // every other zone. Returning `true` tells the framework "we
      // handled it" so the engine doesn't double-report.
      WidgetsBinding.instance.platformDispatcher.onError = (
        Object error,
        StackTrace stack,
      ) {
        if (optIn) {
          FirebaseCrashlytics.instance.recordError(error, stack);
        } else {
          developer.log(
            'Async error (Crashlytics opt-out, not forwarded).',
            name: 'awatv.observability',
            error: error,
            stackTrace: stack,
          );
        }
        return true;
      };
    } on Object catch (e, st) {
      developer.log(
        'Crashlytics setup failed (continuing without crash reporting).',
        name: 'awatv.observability',
        error: e,
        stackTrace: st,
      );
    }

    try {
      await FirebaseAnalytics.instance
          .setAnalyticsCollectionEnabled(optIn);
    } on Object catch (e, st) {
      developer.log(
        'Analytics setup failed (continuing without telemetry).',
        name: 'awatv.observability',
        error: e,
        stackTrace: st,
      );
    }

    _initialised = true;
  }

  /// Persist the opt-in flag and surface a hint that the change takes
  /// effect on next launch (Crashlytics' collection toggle is sticky for
  /// the lifetime of the process — we cannot retroactively disable a
  /// session that already started reporting).
  static Future<void> setOptIn({required bool optIn}) async {
    try {
      final box = Hive.isBoxOpen(prefsBoxName)
          ? Hive.box<dynamic>(prefsBoxName)
          : await Hive.openBox<dynamic>(prefsBoxName);
      await box.put(optInKey, optIn);
    } on Object catch (e, st) {
      developer.log(
        'Failed to persist observability opt-in.',
        name: 'awatv.observability',
        error: e,
        stackTrace: st,
      );
    }

    // Best-effort: try to update the live SDK setting too. On a fresh
    // session this is a no-op (init bailed), and that's fine — the boot
    // path on next launch picks up the new flag from Hive.
    if (_initialised && !kIsWeb) {
      try {
        await FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(optIn);
        await FirebaseAnalytics.instance
            .setAnalyticsCollectionEnabled(optIn);
      } on Object {
        // Non-fatal — see comment above.
      }
    }
  }

  /// Read the persisted opt-in flag. Default is **false** (privacy-first).
  /// Used by the settings switch to seed its initial value.
  static bool readOptIn() {
    try {
      if (!Hive.isBoxOpen(prefsBoxName)) return false;
      final box = Hive.box<dynamic>(prefsBoxName);
      return box.get(optInKey, defaultValue: false) == true;
    } on Object {
      return false;
    }
  }

  /// Helper for feature code that wants to log an analytics event but
  /// must respect the user's opt-out. No-op when init hasn't run yet.
  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    if (!_initialised || kIsWeb) return;
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } on Object {
      // Telemetry is best-effort; don't surface failures to UI.
    }
  }
}
