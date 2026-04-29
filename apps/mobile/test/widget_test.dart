import 'package:awatv_mobile/src/app/awa_tv_app.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // easy_localization writes to SharedPreferences for locale persistence.
  // The test binding uses an in-memory implementation, so we just need
  // to ensure it's initialised before the first MaterialApp build.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('AwaTvApp boots and renders MaterialApp', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const <Locale>[Locale('tr'), Locale('en')],
        path: 'assets/i18n',
        fallbackLocale: const Locale('tr'),
        useOnlyLangCode: true,
        // The asset bundle in unit tests doesn't ship our JSON. Use the
        // explicit AssetLoader fallback so EasyLocalization doesn't
        // throw during boot when the JSON is unreachable; the
        // translation table simply stays empty and `tr()` returns
        // the keys verbatim — which is fine for this smoke test.
        assetLoader: const _NoopAssetLoader(),
        child: const ProviderScope(child: AwaTvApp()),
      ),
    );
    // First frame: router redirect resolves & we expect *some* MaterialApp.
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

/// In-memory stub for easy_localization's asset loader. Used by tests
/// that don't ship a real `assets/i18n/` bundle. Always returns an
/// empty translation map so the package boots cleanly.
class _NoopAssetLoader extends AssetLoader {
  const _NoopAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return <String, dynamic>{};
  }
}
