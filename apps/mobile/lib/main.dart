import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/app/awa_tv_app.dart';
import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/desktop/desktop_window.dart';
import 'package:awatv_mobile/src/desktop/system_tray.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
import 'package:awatv_mobile/src/tv/tv_runtime.dart';
import 'package:awatv_player/awatv_player.dart';
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

  try {
    await AwatvStorage.instance.init(subDir: subDir);
  } on Object {
    // Storage failure means most features won't persist — surface that
    // via the home screen instead of crashing here.
  }

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

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AwaTvApp(),
    ),
  );
}
