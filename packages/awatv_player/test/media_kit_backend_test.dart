// Smoke tests for the MediaKit backend wrapper. We don't actually open
// a stream (libmpv isn't available in the host test runner), but we
// exercise:
//
//   * MediaSource public surface (variants, copyWithUrl, isHls/isDash)
//   * PlayerBackend enum exhaustion
//   * PlayerBackendCapabilities consistency
//   * PlayerException / PlayerBackendUnsupported toString contracts
//
// Live `Player` construction is deferred because it requires libmpv
// natives that are not available in CI runners by default.

import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_player/src/awa_player_controller.dart' as ctrl;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaSource basics', () {
    test('preserves all constructor fields', () {
      const source = MediaSource(
        url: 'http://example.test/stream.m3u8',
        userAgent: 'AWAtv/Test',
        referer: 'http://example.test/',
        headers: <String, String>{'X-Foo': 'bar'},
        title: 'Test Stream',
        subtitleUrl: 'http://example.test/sub.srt',
      );
      expect(source.url, 'http://example.test/stream.m3u8');
      expect(source.userAgent, 'AWAtv/Test');
      expect(source.referer, 'http://example.test/');
      expect(source.title, 'Test Stream');
      expect(source.subtitleUrl, 'http://example.test/sub.srt');
      expect(source.headers, containsPair('X-Foo', 'bar'));
    });

    test('isHls is true for .m3u8 URLs', () {
      const a = MediaSource(url: 'http://x.test/a.m3u8');
      const b = MediaSource(url: 'http://x.test/A.M3U8');
      expect(a.isHls, isTrue);
      expect(b.isHls, isTrue);
    });

    test('isHls is false for non-m3u8 URLs', () {
      const a = MediaSource(url: 'http://x.test/a.ts');
      const b = MediaSource(url: 'http://x.test/a.mp4');
      expect(a.isHls, isFalse);
      expect(b.isHls, isFalse);
    });

    test('isDash is true for .mpd URLs', () {
      const a = MediaSource(url: 'http://x.test/a.mpd');
      expect(a.isDash, isTrue);
    });

    test('copyWithUrl preserves metadata', () {
      const source = MediaSource(
        url: 'http://a',
        userAgent: 'AWAtv',
        referer: 'http://x',
        headers: <String, String>{'A': '1'},
        title: 'T',
        subtitleUrl: 'http://x.srt',
      );
      final copy = source.copyWithUrl('http://b');
      expect(copy.url, 'http://b');
      expect(copy.userAgent, source.userAgent);
      expect(copy.referer, source.referer);
      expect(copy.headers, source.headers);
      expect(copy.title, source.title);
      expect(copy.subtitleUrl, source.subtitleUrl);
    });
  });

  group('MediaSource.variants', () {
    test('builds one entry per URL with shared metadata', () {
      final list = MediaSource.variants(
        const <String>['http://a', 'http://b', 'http://c'],
        userAgent: 'AWAtv',
        referer: 'http://x',
      );
      expect(list, hasLength(3));
      for (final s in list) {
        expect(s.userAgent, 'AWAtv');
        expect(s.referer, 'http://x');
      }
      expect(list[0].url, 'http://a');
      expect(list[1].url, 'http://b');
      expect(list[2].url, 'http://c');
    });

    test('empty input returns empty list', () {
      final list = MediaSource.variants(const <String>[]);
      expect(list, isEmpty);
    });

    test('preserves subtitle URL on every variant', () {
      final list = MediaSource.variants(
        const <String>['http://a', 'http://b'],
        subtitleUrl: 'http://x/sub.srt',
      );
      for (final s in list) {
        expect(s.subtitleUrl, 'http://x/sub.srt');
      }
    });
  });

  group('PlayerBackend enum', () {
    test('has the three documented variants', () {
      expect(
        ctrl.PlayerBackend.values,
        containsAll(<ctrl.PlayerBackend>[
          ctrl.PlayerBackend.auto,
          ctrl.PlayerBackend.mediaKit,
          ctrl.PlayerBackend.vlc,
        ]),
      );
      // Exactly three — guards against silent additions.
      expect(ctrl.PlayerBackend.values.length, 3);
    });

    test('names are stable for persistence', () {
      // Riverpod controllers persist the chosen backend by enum name —
      // changing these is a breaking change.
      expect(ctrl.PlayerBackend.auto.name, 'auto');
      expect(ctrl.PlayerBackend.mediaKit.name, 'mediaKit');
      expect(ctrl.PlayerBackend.vlc.name, 'vlc');
    });
  });

  group('PlayerBackendCapabilities', () {
    test('exposes a vlcReason hint when unsupported', () {
      // If vlc is unsupported, the reason must be a non-empty hint.
      if (!ctrl.PlayerBackendCapabilities.vlcSupported) {
        expect(ctrl.PlayerBackendCapabilities.vlcReason, isNotEmpty);
      }
    });

    test('boolean and reason form a coherent pair', () {
      // Whatever the platform, the reason string is allowed to be
      // empty *only* when supported is true.
      if (ctrl.PlayerBackendCapabilities.vlcReason.isEmpty) {
        expect(ctrl.PlayerBackendCapabilities.vlcSupported, isTrue);
      }
    });
  });

  group('Exceptions', () {
    test('PlayerBackendUnsupported toString embeds backend + reason', () {
      final ex = ctrl.PlayerBackendUnsupported(
        ctrl.PlayerBackend.vlc,
        'VLC not on this platform',
      );
      final s = ex.toString();
      expect(s, contains('vlc'));
      expect(s, contains('VLC not on this platform'));
    });

    test('PlayerException toString includes message', () {
      final ex = ctrl.PlayerException('bad URL');
      expect(ex.toString(), contains('bad URL'));
    });

    test('PlayerException toString includes cause when present', () {
      final ex = ctrl.PlayerException('boom', StateError('inner'));
      expect(ex.toString(), contains('boom'));
      expect(ex.toString(), contains('inner'));
    });

    test('PlayerException with null cause renders cleanly', () {
      final ex = ctrl.PlayerException('plain message');
      // Should not contain "(cause:" segment when cause is null.
      expect(ex.toString(), isNot(contains('(cause:')));
    });
  });
}
