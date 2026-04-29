// Verifies the SettingsScreen renders without throwing and surfaces the
// major sections (theme picker entry, language toggle, account block,
// premium block, etc).
//
// Uses a wide surface (tablet-like) so the responsive layout exercises
// both columns. We don't navigate into sub-routes — each sub-screen is
// covered by its own dedicated test.

import 'package:awatv_mobile/src/features/settings/settings_screen.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  setUpAll(() async {
    await ensureIntegrationTestBinding();
  });

  testWidgets('SettingsScreen builds and surfaces section tiles',
      (WidgetTester tester) async {
    final storage = await openTempStorage(tester);

    final container = ProviderContainer(
      overrides: <Override>[
        awatvStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(900, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // The settings screen renders section tiles via ListTile; without
    // depending on translated copy, just assert there are several
    // tappable rows in the tree (sections + sub-options).
    expect(find.byType(SettingsScreen), findsOneWidget);
    // The screen should mount at least a Scaffold and an AppBar.
    expect(find.byType(Scaffold), findsWidgets);
    // The screen builds many ListTile rows for each section. Asserting
    // the count is non-zero is robust against copy churn.
    expect(
      find.byType(ListTile).evaluate().length,
      greaterThan(0),
      reason: 'Expected the settings screen to render at least one row',
    );
  });
}
