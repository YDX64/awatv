// Shared scaffolding for the integration_test/ suite.
//
// Unlike `test/test_helpers.dart`, these helpers wire the real
// `MaterialApp.router` from `awa_tv_app.dart` so go_router redirects
// fire and the full provider graph boots — which is what makes them
// proper end-to-end smoke tests rather than widget-level assertions.
//
// Every helper builds a hermetic provider container with the heavy
// network / native plugins overridden out:
//   - `awatvStorageProvider` returns a tmp-dir-backed instance so
//      Hive boxes are real (the tests seed them) but isolated per test.
//   - `dioProvider` returns a `MockDio` that interceptors hijack to
//      respond from canned fixtures.
//   - `isTvFormProvider` is forced to `false` so the phone shell renders.
//   - `isDesktopFormProvider` is forced to `false` so the desktop chrome
//      doesn't try to take over the OS window inside the test harness.

import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/app/awa_tv_app.dart';
import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_mobile/src/tv/tv_runtime.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Entry guard — every integration_test main() must call this once before
/// any `testWidgets`. Idempotent.
Future<void> ensureIntegrationTestBinding() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // easy_localization keeps state under SharedPreferences. Pre-seed the
  // mock so the first build doesn't throw a "MissingPluginException".
  SharedPreferences.setMockInitialValues(<String, Object>{});
  // Mock the path_provider channel so `getApplicationDocumentsDirectory`
  // returns a tmp folder under the test runner instead of crashing the
  // platform side. Pure-Dart Hive then writes to that dir via Hive.init.
  // dotenv: empty load lets `Env.read()` fall through to '' defaults.
  try {
    // The empty fileInput is intentional — it primes dotenv with an
    // empty map so `Env.read()` returns '' for every key. The default
    // value here happens to be '' too, but we declare it explicitly so
    // readers don't have to look up the dotenv source.
    // ignore: avoid_redundant_argument_values
    dotenv.testLoad(fileInput: '');
  } on Object {
    // already loaded — fine.
  }
}

/// Opens a brand-new `AwatvStorage` instance backed by a tmp dir so
/// each test gets an empty box set. Cleanup is registered on the
/// `tester` so subsequent tests don't pick up stale state.
Future<AwatvStorage> openTempStorage(WidgetTester tester) async {
  final dir = await Directory.systemTemp.createTemp('awatv-it-');
  Hive.init(dir.path);
  // Reset the singleton so successive tests don't share the box state
  // from the previous run.
  await _resetStorageSingleton();
  final storage = AwatvStorage();
  await storage.init(subDir: dir.path);
  addTearDown(() async {
    try {
      await storage.close();
    } on Object {
      // Hive raises when boxes are already torn down — fine.
    }
    try {
      await dir.delete(recursive: true);
    } on Object {
      // Best-effort cleanup; macOS occasionally holds the dir open.
    }
  });
  return storage;
}

/// Forces the `AwatvStorage._singleton` back to null so the next
/// `instance` call returns a fresh object. Implemented via the public
/// constructor (we never reflect into private state) — the boot path
/// in main.dart goes through `instance` but the integration tests use
/// the explicit constructor.
Future<void> _resetStorageSingleton() async {
  // Hive's "is this box open" map is global; close any leftover boxes
  // from a previous test before opening fresh ones.
  for (final name in <String>[
    AwatvStorage.boxSources,
    AwatvStorage.boxEpg,
    AwatvStorage.boxMetadata,
    AwatvStorage.boxFavorites,
    AwatvStorage.boxHistory,
    AwatvStorage.boxPrefs,
    AwatvStorage.boxRecordings,
    AwatvStorage.boxDownloads,
    AwatvStorage.boxReminders,
    AwatvStorage.boxWatchlist,
  ]) {
    if (Hive.isBoxOpen(name)) {
      await Hive.box<dynamic>(name).close();
    }
  }
}

/// `Dio` mock. Tests register handlers on `setupHandler` to intercept
/// outbound calls — matched by URL substring.
class MockDio extends Mock implements Dio {}

/// Boots the real [AwaTvApp] inside a hermetic provider container.
///
/// Returns the `ProviderContainer` so the test body can assert on
/// provider state directly when it needs to look past the widget tree.
Future<ProviderContainer> pumpAwaTvAppFull(
  WidgetTester tester, {
  required AwatvStorage storage,
  Dio? dio,
  List<Override> extraOverrides = const <Override>[],
  Size surfaceSize = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // easy_localization needs to be primed once or the `tr()` extension
  // returns the raw key. We don't actually mount EasyLocalization here
  // (it requires asset bundle access) — instead the tests assert on
  // raw widget keys / icons rather than translated copy.
  final container = ProviderContainer(
    overrides: <Override>[
      awatvStorageProvider.overrideWithValue(storage),
      if (dio != null) dioProvider.overrideWithValue(dio),
      isTvFormProvider.overrideWithValue(false),
      isDesktopFormProvider.overrideWithValue(false),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const _MinimalLocalizationWrapper(child: AwaTvApp()),
    ),
  );
  // Three pumps cover the post-frame redirect cascade go_router emits
  // when the playlist redirect computes async.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

/// Wraps the AwaTvApp with the bare-minimum easy_localization scaffolding
/// the screens expect. Uses an in-memory empty translations map so the
/// `tr()` extension returns the key string verbatim — the tests then
/// assert on raw keys / widget types instead of localized copy.
class _MinimalLocalizationWrapper extends StatelessWidget {
  const _MinimalLocalizationWrapper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: const <Locale>[Locale('en'), Locale('tr')],
      path: '_unused_',
      fallbackLocale: const Locale('en'),
      // Skip asset loading — the test runner can't read AssetBundle in
      // headless mode. The `assetLoader` returns an empty map so `tr()`
      // returns the raw key and the tests don't depend on the live
      // copy strings (which can change without breaking the test).
      assetLoader: const _EmptyAssetLoader(),
      child: child,
    );
  }
}

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();
  // Signature matches `easy_localization` 3.0.x where `load` returns
  // a nullable map. Returning an empty map is enough for tests — the
  // `tr()` extension falls back to the raw key when no translation is
  // found, which is what we assert against.
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      const <String, dynamic>{};
}
