// Smoke tests for the VLC backend wrapper.
//
// VLC is iOS / Android only. The wrapper guards every public factory
// behind `PlayerBackendCapabilities.vlcSupported`. On a desktop test
// runner (which is where CI runs) the guard short-circuits, so we
// verify the platform-detection logic does the right thing without
// needing libVLC natives at all.

import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_player/src/awa_player_controller.dart' as ctrl;
import 'package:awatv_player/src/backends/vlc_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Platform support gating', () {
    test('VlcPlayerBackend.empty throws on unsupported platforms', () {
      // The unit-test runner is desktop (macOS / Linux / Windows). VLC
      // wrapper is gated to iOS+Android only, so the constructor must
      // refuse rather than create a half-initialised controller.
      if (!ctrl.PlayerBackendCapabilities.vlcSupported) {
        expect(
          VlcPlayerBackend.empty,
          throwsA(isA<ctrl.PlayerBackendUnsupported>()),
        );
      } else {
        // On supported platforms we can at least construct without
        // throwing. We don't open() because that needs platform glue.
        final backend = VlcPlayerBackend.empty();
        expect(backend.backend, ctrl.PlayerBackend.vlc);
        addTearDown(backend.dispose);
      }
    });

    test('VlcPlayerBackend.fromSource throws on unsupported platforms', () {
      const source = MediaSource(url: 'http://example.test/stream.m3u8');
      if (!ctrl.PlayerBackendCapabilities.vlcSupported) {
        expect(
          () => VlcPlayerBackend.fromSource(source),
          throwsA(isA<ctrl.PlayerBackendUnsupported>()),
        );
      }
    });

    test('reason is informative on unsupported platforms', () {
      if (!ctrl.PlayerBackendCapabilities.vlcSupported) {
        final reason = ctrl.PlayerBackendCapabilities.vlcReason;
        expect(reason, isNotEmpty);
        // Must hint at the platform mismatch so the UI can surface a
        // sensible toast.
        expect(
          reason.toLowerCase(),
          anyOf(
            contains('ios'),
            contains('android'),
            contains('platform'),
            contains('not'),
            contains('vlc'),
          ),
        );
      }
    });

    test('PlayerBackendUnsupported carries vlc backend label', () {
      final ex = ctrl.PlayerBackendUnsupported(
        ctrl.PlayerBackend.vlc,
        ctrl.PlayerBackendCapabilities.vlcReason,
      );
      expect(ex.backend, ctrl.PlayerBackend.vlc);
      expect(ex.toString(), contains('vlc'));
    });
  });

  group('Backend identity', () {
    test('reports vlc as its backend type', () {
      // We can only assert this when the backend can actually be
      // constructed. On unsupported platforms we already covered the
      // throwing path above.
      if (ctrl.PlayerBackendCapabilities.vlcSupported) {
        final backend = VlcPlayerBackend.empty();
        addTearDown(backend.dispose);
        expect(backend.backend, ctrl.PlayerBackend.vlc);
      }
    });
  });
}
