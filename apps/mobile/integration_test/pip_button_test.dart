// Verifies the desktop PiP toggle. Skipped on web/mobile — PiP only
// makes sense where window_manager is wired up.
//
// We exercise the provider directly rather than driving the window
// manager (the real plugin requires a real Cocoa/Win32 window which
// the test harness can't provide). Asserts:
//   * pipModeProvider starts at false.
//   * Calling `set(true)` flips the provider.
//   * The PipMode notifier persists state across reads.

import 'package:awatv_mobile/src/desktop/pip_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  setUpAll(() async {
    await ensureIntegrationTestBinding();
  });

  testWidgets('pipModeProvider toggles when notifier .set is called',
      (WidgetTester tester) async {
    // Web has no PiP path — skip without failing.
    if (kIsWeb) {
      // Empty body; assertion skipped on web.
      expect(kIsWeb, isTrue);
      return;
    }

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(pipModeProvider), isFalse);

    container.read(pipModeProvider.notifier).set(true);
    expect(container.read(pipModeProvider), isTrue);

    container.read(pipModeProvider.notifier).set(false);
    expect(container.read(pipModeProvider), isFalse);
  });
}
