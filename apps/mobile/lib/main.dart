import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/app/awa_tv_app.dart';
import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/desktop/desktop_window.dart';
import 'package:awatv_mobile/src/desktop/system_tray.dart';
import 'package:awatv_mobile/src/shared/background_playback/audio_session_config.dart';
import 'package:awatv_mobile/src/shared/background_playback/background_playback_controller.dart';
import 'package:awatv_mobile/src/shared/notifications/notifications_provider.dart';
import 'package:awatv_mobile/src/shared/observability/awatv_observability.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
import 'package:awatv_mobile/src/tv/tv_runtime.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AWAtv mobile entry point.
///
/// Boots in this order — order matters:
/// 1. Flutter binding (so `WidgetsBinding` is available pre-`runApp`).
/// 2. `.env` file (TMDB key, AdMob ids, …) via `flutter_dotenv`.
/// 3. Hive — uses IndexedDB on web, file system elsewhere.
/// 4. Optional: video-player engine (skipped on web; media_kit needs libmpv).
/// 5. `AwatvStorage` — opens all the typed Hive boxes the services need.
/// 6. `runApp` wrapped in a `ProviderScope`.
///
/// Every external init step is wrapped in try/catch so a misconfigured
/// platform never produces a blank black screen — the app boots and the
/// degraded feature surfaces a friendly error instead.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // easy_localization needs SharedPreferences to remember the user's
  // last picked locale and the JSON loader to resolve translation keys.
  // Failure is non-fatal: in degraded mode the `tr()` extension still
  // returns the key string, so the UI keeps rendering English-ish copy.
  try {
    await EasyLocalization.ensureInitialized();
  } on Object {
    // Continue boot even if shared_prefs is unavailable (rare on web).
  }

  try {
    await dotenv.load();
  } on Object {
    // .env missing in dev / web — keys default to empty strings via `Env`.
  }

  // Hive: on web this maps to IndexedDB; subDir is ignored. On native we
  // pass a writable application-documents path so boxes survive restarts.
  String? subDir;
  if (!kIsWeb) {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      subDir = docsDir.path;
    } on Object {
      // Fall back to platform default (`Hive.initFlutter` cwd).
    }
  }

  await Hive.initFlutter('awatv');

  // media_kit: native libmpv on iOS/Android/desktop, HTML5 video on web.
  // Wrap so a web fallback that lacks codec support never bricks the boot.
  try {
    await AwaPlayerController.ensureInitialized();
  } on Object {
    // Player will still create on demand; web users may see a "couldn't
    // play this stream" surface for HEVC/AV1 but the app boots.
  }

  // Audio session — tells the OS we are a media-playback app so the
  // engine keeps decoding while the screen is locked / app backgrounded.
  // No-op on web. Failures are non-fatal; the player still renders.
  try {
    await configureAudioSession();
  } on Object {
    // Without a session we lose lock-screen / Bluetooth control UX,
    // but on-screen playback still works.
  }

  // Boot the OS media-session bridge. On Android this also wires the
  // foreground-service notification, so streams can survive the doze
  // killer for the duration the user keeps playback alive. On iOS /
  // macOS this populates the lock-screen / Control Center tile.
  try {
    await ensureAudioServiceInitialized();
  } on Object {
    // Best-effort — see comment above; failure here only loses the
    // lock-screen affordance.
  }

  try {
    await AwatvStorage.instance.init(subDir: subDir);
  } on Object {
    // Storage failure means most features won't persist — surface that
    // via the home screen instead of crashing here.
  }

  // Firebase observability (Crashlytics + Analytics). Privacy-first:
  // collection is *off* by default and only enabled once the user
  // flips the switch in Settings → Gizlilik. The opt-in flag lives in
  // the shared 'prefs' Hive box, opened on demand inside
  // `AwatvObservability` to avoid a hard ordering dep with
  // `AwatvStorage`. Failures (missing google-services config, web,
  // unsupported platform) are completely silent — see the wrapper.
  //
  // The future is intentionally not awaited: a slow / unreachable
  // Firebase project must never delay the first frame.
  unawaited(
    () async {
      try {
        // Open the prefs box up-front (it's idempotent if already open
        // elsewhere). This way the boot path can read the opt-in flag
        // without forcing every consumer to remember to open it.
        if (!Hive.isBoxOpen(AwatvObservability.prefsBoxName)) {
          await Hive.openBox<dynamic>(AwatvObservability.prefsBoxName);
        }
        // GDPR-granular: each subsystem's collection is gated on its
        // own toggle. Crashlytics off / Analytics on (or vice versa)
        // are valid combinations.
        final crashlyticsOptIn = AwatvObservability.readCrashlyticsOptIn();
        final analyticsOptIn = AwatvObservability.readAnalyticsOptIn();
        await AwatvObservability.initialise(
          crashlyticsOptIn: crashlyticsOptIn,
          analyticsOptIn: analyticsOptIn,
        );
      } on Object {
        // Wrapped twice on purpose — the inner wrapper logs, this one
        // guarantees the outer fire-and-forget cannot throw.
      }
    }(),
  );

  // Supabase: optional cloud-sync backend. The app remains fully usable
  // (guest mode, on-device only) when these env vars are blank or when
  // initialise itself throws — a misconfigured backend never blocks boot.
  if (Env.hasSupabase) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
        debug: kDebugMode,
      );
    } on Object {
      // Init failure → app continues in guest mode. AuthController
      // detects the absence of a live client and emits AuthGuest.
    }
  }

  // Desktop only: take over the OS window before runApp so the first
  // frame already has the right size and (on macOS) a hidden titlebar.
  // Pure no-op on iOS / Android / web.
  if (!kIsWeb && isDesktopRuntime()) {
    try {
      await initialiseDesktopWindow();
    } on Object {
      // Window init is cosmetic; ignore failures.
    }
  }

  // One-shot form-factor probe. The same APK is shipped to phones and
  // Android TV; a heuristic on `PlatformDispatcher.views.first` decides
  // which shell renders. See `TvRuntime.detectFromPlatform`.
  final isTv = TvRuntime.detectFromPlatform();

  // Build the ProviderContainer up-front so we can wire the tray
  // *before* runApp — this guarantees the tray's listener on
  // `activePlaybackProvider` is in place before any player route can
  // emit a now-playing event.
  final container = ProviderContainer(
    overrides: <Override>[
      isTvFormProvider.overrideWithValue(isTv),
    ],
  );

  // Tray initialisation. Wrapped because tray_manager has spotty Linux
  // support and any platform glitch must not block the boot.
  if (!kIsWeb && isDesktopRuntime()) {
    try {
      await container.read(systemTrayProvider);
    } on Object {
      // Tray init failure is non-fatal — the app still works without it.
    }
  }

  // Profile bootstrap — guarantees at least one profile exists before
  // any screen reads `activeProfileProvider`. The default profile keeps
  // the legacy un-scoped favourites + history boxes, so users upgrading
  // from a pre-profiles build see their data on the right tile.
  try {
    await container.read(profileControllerProvider).bootstrapDefaultProfile();
  } on Object {
    // Worst case: profile-scoped boxes don't open. Fav/history fall
    // back to the legacy global boxes; the picker just renders empty
    // until the user creates a profile manually.
  }

  // Local notifications: register the OS channel + tap callback. We do
  // *not* request notification permission here — that's deferred to the
  // first time the user taps "Hatirlat" on an EPG programme. Failure
  // (no plugin on this platform, missing tz data) is non-fatal.
  if (!kIsWeb) {
    try {
      await container.read(awatvNotificationsProvider).init();
    } on Object {
      // Schedules will surface their own error UI when the user tries
      // to add a reminder; the rest of the app keeps booting.
    }
    // Reschedule any persisted reminders that the OS may have lost
    // (device reboot, app reinstall). Best-effort.
    unawaited(
      () async {
        try {
          await container.read(remindersServiceProvider).rescheduleAll();
        } on Object {
          // Logged inside the service; nothing to do here.
        }
      }(),
    );
  }

  runApp(
    EasyLocalization(
      // Two locales today: Turkish (default + fallback) and English.
      // Adding a new language is a matter of dropping
      // `assets/i18n/<code>.json` next to the existing files and adding
      // the locale here — the Settings → Dil chooser picks them up via
      // `context.supportedLocales` automatically.
      supportedLocales: const <Locale>[
        Locale('tr'),
        Locale('en'),
      ],
      path: 'assets/i18n',
      fallbackLocale: const Locale('tr'),
      // Use device locale on first launch; pin to TR if the device is
      // on a language we don't have JSON for so the UI never falls back
      // to raw key strings.
      useOnlyLangCode: true,
      child: UncontrolledProviderScope(
        container: container,
        child: const AwaTvApp(),
      ),
    ),
  );
}
