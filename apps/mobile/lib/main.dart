import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/app/awa_tv_app.dart';
import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/desktop/desktop_window.dart';
import 'package:awatv_mobile/src/tv/tv_runtime.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// AWAtv mobile entry point.
///
/// Boots in this order — order matters:
/// 1. Flutter binding (so `WidgetsBinding` is available pre-`runApp`).
/// 2. `.env` file (TMDB key, AdMob ids, …) via `flutter_dotenv`.
/// 3. Hive (file-backed key/value store) under the app's documents dir.
/// 4. The video-player engine (`media_kit` registration in awatv_player).
/// 5. `AwatvStorage` — opens all the typed Hive boxes the services need.
/// 6. `runApp` wrapped in a `ProviderScope`.
///
/// `dotenv.load` tolerates a missing `.env` file in dev / test by catching
/// the load error so the app still boots when the developer hasn't filled
/// in their secrets yet.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load();
  } on Object {
    // .env not yet provided — keys default to empty strings via `Env`.
  }

  final docsDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter('awatv');
  await AwaPlayerController.ensureInitialized();
  await AwatvStorage.instance.init(subDir: docsDir.path);

  // Desktop only: take over the OS window before runApp so the first
  // frame already has the right size and (on macOS) a hidden titlebar.
  // Pure no-op on iOS / Android / web.
  if (isDesktopRuntime()) {
    await initialiseDesktopWindow();
  }

  // One-shot form-factor probe. The same APK is shipped to phones and
  // Android TV; a heuristic on `PlatformDispatcher.views.first` decides
  // which shell renders. See `TvRuntime.detectFromPlatform`.
  final isTv = TvRuntime.detectFromPlatform();

  runApp(
    ProviderScope(
      overrides: <Override>[
        isTvFormProvider.overrideWithValue(isTv),
      ],
      child: const AwaTvApp(),
    ),
  );
}
