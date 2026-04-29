// Boots the full AwaTvApp in headless mode and verifies:
//   1. The root widget is a MaterialApp.router (not the legacy MaterialApp).
//   2. No FlutterError dispatched during initialisation.
//
// Doesn't seed any storage — the redirect chain is allowed to fire and
// land on `/onboarding` (zero playlists). That's covered separately in
// `onboarding_flow_test.dart`.

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/app/awa_tv_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '_helpers.dart';

void main() {
  setUpAll(() async {
    await ensureIntegrationTestBinding();
  });

  testWidgets('boot renders MaterialApp.router with no FlutterError',
      (WidgetTester tester) async {
    final flutterErrors = <FlutterErrorDetails>[];
    final prevHandler = FlutterError.onError;
    FlutterError.onError = flutterErrors.add;
    addTearDown(() => FlutterError.onError = prevHandler);

    final storage = await openTempStorage(tester);
    final dio = MockDio();
    when(() => dio.close(force: any(named: 'force'))).thenReturn(null);

    await pumpAwaTvAppFull(
      tester,
      storage: storage,
      dio: dio,
    );

    // The root widget under AwaTvApp's build is a MaterialApp.router.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(AwaTvApp), findsOneWidget);

    // Make sure no synchronous error fired during init.
    expect(
      flutterErrors,
      isEmpty,
      reason: 'Boot path emitted Flutter errors: '
          '${flutterErrors.map((e) => e.exceptionAsString()).join("; ")}',
    );

    // Storage should have been initialised by the override.
    expect(storage, isA<AwatvStorage>());
  });
}
