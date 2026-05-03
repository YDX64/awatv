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

  /// Legacy single-flag key — kept for backward compatibility with
  /// installs that completed onboarding before the GDPR-granular
  /// refactor. New code reads/writes [crashlyticsOptInKey] and
  /// [analyticsOptInKey] separately.
  static const String optInKey = 'observability.optIn';

  /// Hive key for the Crashlytics-only opt-in. Crash reports include
  /// device + OS metadata + stack traces. GDPR Art. 13 transparency
  /// requirement: separate toggle from analytics.
  static const String crashlyticsOptInKey = 'observability.crashlytics';

  /// Hive key for the Analytics-only opt-in. Usage events
  /// (screen views, feature engagement). More invasive than crash
  /// reporting — separate toggle is required for granular consent.
  static const String analyticsOptInKey = 'observability.analytics';

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
  /// GDPR-granular: each subsystem honours its own preference. Pass
  /// `false` for both to satisfy a "Hepsini Reddet" choice; pass mixed
  /// values when the user only opted into crash reports.
  ///
  /// Even when both are `false` we still call `Firebase.initializeApp`
  /// so a subsequent toggle flip can flush queued reports without a
  /// full app restart.
  static Future<void> initialise({
    required bool crashlyticsOptIn,
    required bool analyticsOptIn,
  }) async {
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
      // Crashlytics gated on its OWN flag — analytics opt-in alone does
      // NOT enable crash reporting. GDPR Art. 7(2): each consent must
      // be independent.
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(crashlyticsOptIn);

      // Capture FlutterError.onError. We always *log* to developer.log
      // so devs see the stack in DevTools, but only forward to
      // Crashlytics when the user has opted in for crash reports
      // specifically.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (crashlyticsOptIn) {
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
        if (crashlyticsOptIn) {
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
      // Analytics has its OWN flag. A user who opted into crash reports
      // but rejected analytics gets event collection disabled here.
      await FirebaseAnalytics.instance
          .setAnalyticsCollectionEnabled(analyticsOptIn);
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

  /// Legacy setter — sets BOTH flags to the same value. Retained so
  /// existing call sites continue to compile during the migration; new
  /// code should call [setCrashlyticsOptIn] / [setAnalyticsOptIn]
  /// independently.
  static Future<void> setOptIn({required bool optIn}) async {
    await setCrashlyticsOptIn(optIn);
    await setAnalyticsOptIn(optIn);
  }

  /// Persist the Crashlytics opt-in flag. Crashlytics' collection toggle
  /// is sticky for the lifetime of the process — toggling here does
  /// best-effort live updates, but the canonical effect is on next boot.
  // ignore: avoid_positional_boolean_parameters
  static Future<void> setCrashlyticsOptIn(bool optIn) async {
    await _writeFlag(crashlyticsOptInKey, optIn);
    if (_initialised && !kIsWeb) {
      try {
        await FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(optIn);
      } on Object {
        // Non-fatal — see initialise() comment above.
      }
    }
  }

  /// Persist the Analytics opt-in flag. Same boot-sticky semantics as
  /// [setCrashlyticsOptIn] — the runtime toggle is best-effort, the
  /// authoritative read happens on next launch.
  // ignore: avoid_positional_boolean_parameters
  static Future<void> setAnalyticsOptIn(bool optIn) async {
    await _writeFlag(analyticsOptInKey, optIn);
    if (_initialised && !kIsWeb) {
      try {
        await FirebaseAnalytics.instance
            .setAnalyticsCollectionEnabled(optIn);
      } on Object {
        // Non-fatal — see initialise() comment above.
      }
    }
  }

  /// Legacy reader — true if EITHER flag is on. Retained so existing
  /// settings-screen logic doesn't break during the migration.
  static bool readOptIn() {
    return readCrashlyticsOptIn() || readAnalyticsOptIn();
  }

  /// Read the persisted Crashlytics opt-in. Default is **false**
  /// (privacy-first). Migrates the legacy single-flag value on first
  /// read so users who already opted in pre-v0.5.6 don't get reset.
  static bool readCrashlyticsOptIn() {
    return _readFlagWithLegacyFallback(crashlyticsOptInKey);
  }

  /// Read the persisted Analytics opt-in. Default is **false**
  /// (privacy-first). Same legacy fallback behaviour as
  /// [readCrashlyticsOptIn].
  static bool readAnalyticsOptIn() {
    return _readFlagWithLegacyFallback(analyticsOptInKey);
  }

  // -----------------------------------------------------------------------
  // private flag helpers
  // -----------------------------------------------------------------------

  static Future<void> _writeFlag(String key, bool value) async {
    try {
      final box = Hive.isBoxOpen(prefsBoxName)
          ? Hive.box<dynamic>(prefsBoxName)
          : await Hive.openBox<dynamic>(prefsBoxName);
      await box.put(key, value);
    } on Object catch (e, st) {
      developer.log(
        'Failed to persist $key.',
        name: 'awatv.observability',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Returns the granular flag if it's set; otherwise falls back to the
  /// legacy union flag from pre-v0.5.6 installs. Default false when
  /// neither key is present.
  static bool _readFlagWithLegacyFallback(String key) {
    try {
      if (!Hive.isBoxOpen(prefsBoxName)) return false;
      final box = Hive.box<dynamic>(prefsBoxName);
      // If the granular flag was explicitly written (even false), trust it.
      if (box.containsKey(key)) {
        return box.get(key) == true;
      }
      // Otherwise honour the legacy union flag — converts a yes/no from
      // a pre-migration install into the granular world.
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
