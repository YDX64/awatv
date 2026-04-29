import 'package:awatv_mobile/src/app/theme_mode_provider.dart';
import 'package:awatv_mobile/src/desktop/desktop_chrome.dart';
import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/features/themes/custom_theme_builder.dart';
import 'package:awatv_mobile/src/features/themes/custom_theme_controller.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/notifications/notification_tap_router.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_scoped_providers.dart';
import 'package:awatv_mobile/src/shared/sync/cloud_sync_providers.dart';
import 'package:awatv_mobile/src/shared/sync/device_fingerprint.dart';
import 'package:awatv_mobile/src/shared/updater/update_boot_check.dart';
import 'package:awatv_mobile/src/tv/tv_router.dart';
import 'package:awatv_mobile/src/tv/tv_runtime.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root MaterialApp.
///
/// Reads the current `ThemeMode` + custom theme profile from Riverpod
/// and runs them through `CustomThemeBuilder` to produce the active
/// light / dark `ThemeData`. Premium users can swap accent / variant /
/// corner-radius from `/settings/theme`; everyone else gets the
/// historical AWAtv brand palette via [AppCustomTheme.defaults].
/// Routing is delegated to one of two routers:
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
    // Mount the profile-change listener so an active profile switch
    // invalidates the legacy un-scoped favourites/history providers
    // and any UI watching them re-subscribes against fresh data.
    ref.watch(profileSyncListenerProvider);
    final router = isTv
        ? ref.watch(appTvRouterProvider)
        : ref.watch(appRouterProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    // Custom theme — picks up the user's persisted (or live-preview)
    // accent / variant / radius scale. Falls back to the historical
    // BrandColors-seeded look when the user has never opened the
    // theme picker. We always derive light + dark variants so the
    // OS-driven mode switch keeps working without extra wiring.
    final customTheme = ref.watch(customThemeControllerProvider);

    return MaterialApp.router(
      title: 'AWAtv',
      debugShowCheckedModeBanner: false,
      theme: CustomThemeBuilder.build(customTheme, Brightness.light),
      darkTheme: CustomThemeBuilder.build(customTheme, Brightness.dark),
      // TVs have no light theme — leanback launchers and most Android-TV
      // user flows live in the dark. Force dark when running on a TV.
      themeMode: isTv ? ThemeMode.dark : themeMode,
      routerConfig: router,
      // Wrap the entire app shell with the desktop chrome on macOS /
      // Windows / Linux. On TV and mobile this is a no-op pass-through.
      // The `UpdateBootCheck` wrapper kicks off a silent auto-update
      // probe ~5s after first frame on desktop builds and renders a
      // snackbar when a newer release is on offer.
      builder: (BuildContext context, Widget? child) {
        final body = child ?? const SizedBox.shrink();
        // The notification-tap router needs a router context to push,
        // so it must sit *inside* MaterialApp.router's builder. Mount
        // it here so reminder notifications can deep-link into /play
        // / /reminders without going through main.dart.
        final tapped = NotificationTapRouter(child: body);
        final wrapped = UpdateBootCheck(child: tapped);
        if (isDesktop && !isTv) {
          return DesktopChrome(child: wrapped);
        }
        return wrapped;
      },
      // Wire easy_localization. The package's delegates package up the
      // GlobalMaterial / Widgets / Cupertino delegates so we get Material
      // shelf strings (e.g. "next month" in the date picker) localized
      // alongside our own JSON translations. The active locale is
      // persisted by easy_localization itself across app launches.
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }
}
