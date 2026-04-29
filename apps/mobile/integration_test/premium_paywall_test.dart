// Renders the PremiumScreen and verifies:
//   * Three plan-card containers render (monthly / yearly / lifetime).
//   * Calling `simulateActivate(lifetime)` flips the PremiumStatus
//     provider to PremiumTierActive(plan: lifetime).

import 'package:awatv_mobile/src/features/premium/premium_screen.dart';
import 'package:awatv_mobile/src/shared/premium/premium_status_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  setUpAll(() async {
    await ensureIntegrationTestBinding();
  });

  testWidgets('PremiumScreen renders 3 plan tiles + activate flips tier',
      (WidgetTester tester) async {
    final storage = await openTempStorage(tester);

    final container = ProviderContainer(
      overrides: <Override>[
        awatvStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PremiumScreen(),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(PremiumScreen), findsOneWidget);
    // The paywall renders three plan cards; the screen body uses
    // `Card` widgets. Three cards is the minimum; the layout may
    // wrap them in additional decoration so we use >=.
    expect(
      find.byType(Card).evaluate().length,
      greaterThanOrEqualTo(3),
      reason: 'Expected three plan tiles in the paywall',
    );

    // Drive the lifetime activation directly through the provider —
    // this is the same call the screen's CTA invokes after the user
    // taps "Premium ol".
    await container
        .read(premiumStatusProvider.notifier)
        .simulateActivate(PremiumPlan.lifetime);
    await tester.pump();

    final tier = container.read(premiumStatusProvider);
    expect(tier, isA<PremiumTierActive>());
    final active = tier as PremiumTierActive;
    expect(active.plan, PremiumPlan.lifetime);
    // Lifetime never expires.
    expect(active.expiresAt, isNull);
    expect(active.willRenew, isFalse);
  });
}
