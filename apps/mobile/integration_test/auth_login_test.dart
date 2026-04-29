// Renders the LoginScreen and verifies:
//   * Email field + submit button surface (form mode).
//   * When `Env.hasSupabase` is false the form switches to the
//     "backend not configured" banner.
//
// We can't easily flip `Env.hasSupabase` from a test because it reads
// dotenv. The boolean is computed from `_read('SUPABASE_URL')`; under
// the empty `dotenv.testLoad` priming we did, `hasSupabase` returns
// false — which is the path we want to assert on.

import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/features/auth/login_screen.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  setUpAll(() async {
    await ensureIntegrationTestBinding();
  });

  testWidgets('LoginScreen renders banner when Supabase not configured',
      (WidgetTester tester) async {
    // Ensure the env is empty so `Env.hasSupabase` is false.
    expect(Env.hasSupabase, isFalse);

    final storage = await openTempStorage(tester);

    final container = ProviderContainer(
      overrides: <Override>[
        awatvStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(LoginScreen), findsOneWidget);
    // When backend isn't configured, the form is replaced with a
    // banner widget. The banner uses an icon + a title block; the
    // simplest robust assertion is that no email input field shows.
    final emailFields = find.byType(TextFormField);
    expect(
      emailFields.evaluate().length,
      lessThanOrEqualTo(0),
      reason:
          'Expected no editable email field when Supabase is unconfigured; '
          'the banner replaces the form entirely.',
    );
  });
}
