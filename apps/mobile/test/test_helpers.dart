// Shared widget-test helpers.
//
// Wraps a screen-under-test in the minimum scaffolding it needs to
// build cleanly: ProviderScope, MaterialApp, locale + theme. Without
// this, every test file would re-implement the same `pumpWidget`
// boilerplate.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Default locales we test against. The app supports tr + en today.
const List<Locale> kSupportedTestLocales = <Locale>[
  Locale('tr'),
  Locale('en'),
];

/// Pumps [child] inside a ProviderScope + MaterialApp with sensible
/// defaults. Test bodies should call this once and `await
/// tester.pumpAndSettle()` before asserting.
///
/// Pass [overrides] to swap out Riverpod providers for mocks. Pass
/// [locale] to override the default Turkish locale.
Future<void> pumpAwaTvApp(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const <Override>[],
  Locale locale = const Locale('tr'),
  ThemeMode themeMode = ThemeMode.dark,
  Size? surfaceSize,
}) async {
  if (surfaceSize != null) {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: ThemeData(
          brightness: Brightness.light,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        // We don't wire easy_localization here — the screens we test
        // are designed to render reasonable copy without it (most use
        // hard-coded Turkish today). The tests assert on widgets and
        // semantics rather than translated strings.
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: kSupportedTestLocales,
        locale: locale,
        home: child,
      ),
    ),
  );
}

/// Pumps `child` and runs `pump()` repeatedly until the frame queue
/// drains, with a hard timeout to keep tests bounded. Use this when
/// the widget kicks off post-frame async work (Riverpod providers,
/// stream subscriptions) that needs to settle before assertions.
Future<void> pumpAndSettleSafely(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    await tester.pumpAndSettle(timeout);
  } on Object {
    // Some screens schedule infinite tickers (live-pulse / shimmer).
    // Fall back to a fixed-frame pump so tests don't hang.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
}
