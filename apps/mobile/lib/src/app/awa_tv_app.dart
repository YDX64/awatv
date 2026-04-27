import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../routing/app_router.dart';
import 'theme_mode_provider.dart';

/// Root MaterialApp.
///
/// Reads the current `ThemeMode` from Riverpod, hands the dark/light
/// `ThemeData` from `awatv_ui`'s `AppTheme`, and delegates routing to the
/// `appRouterProvider`.
class AwaTvApp extends ConsumerWidget {
  const AwaTvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(appThemeModeProvider);

    return MaterialApp.router(
      title: 'AWAtv',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
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
