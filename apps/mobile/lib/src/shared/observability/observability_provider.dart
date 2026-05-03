import 'package:awatv_mobile/src/shared/observability/awatv_observability.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'observability_provider.g.dart';

/// Live opt-in flag for crash + analytics reporting.
///
/// Backed by Hive — when the user toggles the switch in settings the
/// notifier persists to the `prefs` box and updates the live Firebase
/// SDKs (best-effort; sticky-on-this-process Crashlytics caveat applies
/// to a freshly-flipped *off* in the same session).
@Riverpod(keepAlive: true)
class ObservabilityOptIn extends _$ObservabilityOptIn {
  @override
  bool build() {
    // Default false (privacy-first). The boot path may have flipped
    // this earlier if the user opted in on a previous launch.
    return AwatvObservability.readOptIn();
  }

  /// Persist + push to Firebase. Returns the new value.
  ///
  /// The bool is positional (instead of named) because the caller
  /// pattern is `notifier.setOptIn(true)` — adding a `value:` label
  /// would only obscure the call site.
  // ignore: avoid_positional_boolean_parameters
  Future<bool> setOptIn(bool value) async {
    state = value;
    await AwatvObservability.setOptIn(optIn: value);
    return value;
  }

  /// GDPR-granular setter — Crashlytics only. The onboarding privacy
  /// step calls this on every toggle change so the choice is persisted
  /// before the user advances (no implicit consent on a force-quit
  /// between toggle and continue).
  // ignore: avoid_positional_boolean_parameters
  Future<void> setCrashlyticsOptIn(bool value) async {
    await AwatvObservability.setCrashlyticsOptIn(value);
    state = AwatvObservability.readOptIn();
  }

  /// GDPR-granular setter — Analytics only. Same persistence guarantee
  /// as [setCrashlyticsOptIn].
  // ignore: avoid_positional_boolean_parameters
  Future<void> setAnalyticsOptIn(bool value) async {
    await AwatvObservability.setAnalyticsOptIn(value);
    state = AwatvObservability.readOptIn();
  }

  /// Convenience for a single-tap switch — toggles and returns the new
  /// value so the calling widget can show a snackbar with the right text.
  Future<bool> toggle() => setOptIn(!state);
}

/// True once Firebase has booted in this process. The settings screen
/// uses this to render an "Aktif — bir sonraki acilista uygulanir"
/// hint when the user just flipped the switch.
@Riverpod(keepAlive: true)
bool observabilityInitialised(Ref ref) {
  // Watch the opt-in too so any flip refreshes the dependent UI.
  ref.watch(observabilityOptInProvider);
  return AwatvObservability.isInitialised;
}

/// Eagerly opens the prefs Hive box if missing — the observability layer
/// reads/writes from it, and the rest of the app uses an unkeyed dynamic
/// box for misc preferences. Safe to call from any provider scope.
@Riverpod(keepAlive: true)
Future<Box<dynamic>> prefsBox(Ref ref) async {
  if (Hive.isBoxOpen(AwatvObservability.prefsBoxName)) {
    return Hive.box<dynamic>(AwatvObservability.prefsBoxName);
  }
  return Hive.openBox<dynamic>(AwatvObservability.prefsBoxName);
}
