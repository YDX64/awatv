import 'package:awatv_mobile/src/app/theme_mode_provider.dart';
import 'package:awatv_mobile/src/desktop/desktop_chrome.dart';
import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/sync/cloud_sync_providers.dart';
import 'package:awatv_mobile/src/shared/sync/device_fingerprint.dart';
import 'package:awatv_mobile/src/tv/tv_router.dart';
import 'package:awatv_mobile/src/tv/tv_runtime.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root MaterialApp.
///
/// Reads the current `ThemeMode` from Riverpod, hands the dark/light
/// `ThemeData` from `awatv_ui`'s `AppTheme`, and delegates routing to one
/// of two routers:
///
///   * `appRouterProvider`     — phone / tablet shell (bottom nav).
///   * `appTvRouterProvider`   — Android TV shell (left rail, D-pad).
///
/// The pick is driven by `isTvFormProvider`, which is overridden once at
/// boot in `main.dart` after a one-time form-factor probe. Switching the
/// override at runtime would force a full app rebuild — fine for tests,
/// not used in production.
class AwaTvApp extends ConsumerWidget {
  const AwaTvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTv = ref.watch(isTvFormProvider);
    final isDesktop = ref.watch(isDesktopFormProvider);
    if (isTv) DeviceFingerprint.markCurrentProcessAsTv();
    // Bring the cloud sync engine online whenever this widget is mounted.
    // The pulse provider auto-activates / -deactivates based on the
    // canUseCloudSync gate; just watching it is enough to attach the
    // lifecycle to the running app.
    ref.watch(cloudSyncEnginePulseProvider);
    final router = isTv
        ? ref.watch(appTvRouterProvider)
        : ref.watch(appRouterProvider);
    final themeMode = ref.watch(appThemeModeProvider);

    return MaterialApp.router(
      title: 'AWAtv',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // TVs have no light theme — leanback launchers and most Android-TV
      // user flows live in the dark. Force dark when running on a TV.
      themeMode: isTv ? ThemeMode.dark : themeMode,
      routerConfig: router,
      // Wrap the entire app shell with the desktop chrome on macOS /
      // Windows / Linux. On TV and mobile this is a no-op pass-through.
      builder: (BuildContext context, Widget? child) {
        final body = child ?? const SizedBox.shrink();
        if (isDesktop && !isTv) {
          return DesktopChrome(child: body);
        }
        return body;
      },
      // Default Material localizations — full i18n is wired in Phase 2 via
      // easy_localization (see ROADMAP.md).
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[
        Locale('en'),
        Locale('tr'),
      ],
    );
  }
}
