// Smoke test for the onboarding welcome wrapper. The widget is now a
// thin redirect — when no onboarding completion flag is set it tries
// to push `/onboarding/wizard`. Without a real router that push is a
// no-op; we just verify the loading placeholder renders.

import 'package:awatv_mobile/src/features/onboarding/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'WelcomeScreen renders the loading placeholder',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: WelcomeScreen(),
          ),
        ),
      );
      // Pump one frame — the post-frame callback for the redirect is
      // scheduled but won't be able to navigate (no go_router). The
      // placeholder body should be visible meanwhile.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );
}
