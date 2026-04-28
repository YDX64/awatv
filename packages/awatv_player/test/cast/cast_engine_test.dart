// Smoke tests for the cast engine layer. Verify the platform-aware
// factory picks the right implementation, that the no-op engine
// behaves correctly on unsupported platforms, and that the sealed
// session state is exhaustively constructable.

import 'package:awatv_player/awatv_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The cast engine subscribes to platform event channels at
  // construction time. Without a binding the channels throw on
  // listen — calling ensureInitialized lets us exercise the engine
  // factory in a unit test environment.
  TestWidgetsFlutterBinding.ensureInitialized();

  // The Chromecast / AirPlay engines subscribe to event channels at
  // construction time. The standard test binding has no native
  // implementation behind those channels, so we mock both with empty
  // event streams. This way we can construct the platform engines on
  // the test harness without failing on missing-plugin errors.
  void mockChannel(String name) {
    TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockStreamHandler(
      EventChannel(name),
      MockStreamHandler.inline(
        onListen: (Object? args, MockStreamHandlerEventSink sink) {},
        onCancel: (Object? args) {},
      ),
    );
    TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannel(name.replaceAll('/events', '')),
      (MethodCall call) async => null,
    );
  }

  setUpAll(() {
    mockChannel('awatv/cast/events');
    mockChannel('awatv/airplay/events');
  });

  group('CastEngine.platform', () {
    test('returns a non-null engine on every platform', () async {
      final engine = CastEngine.platform();
      addTearDown(engine.dispose);
      expect(engine, isNotNull);
      expect(engine.currentSession, isA<CastIdle>());
    });

    test('first emission is the cached idle state', () async {
      final engine = CastEngine.platform();
      addTearDown(engine.dispose);
      final first = await engine.sessions().first;
      expect(first, isA<CastIdle>());
    });

    test('NoOp.connect throws CastUnsupportedException', () async {
      final engine = NoOpCastEngine.fromReason('test platform');
      addTearDown(engine.dispose);

      const device = CastDevice(
        id: 'test',
        name: 'Test TV',
        kind: CastDeviceKind.chromecast,
      );
      expect(
        () => engine.connect(device),
        throwsA(isA<CastUnsupportedException>()),
      );
    });

    test('NoOp.startDiscovery is a no-op', () async {
      final engine = NoOpCastEngine.fromReason('test platform');
      addTearDown(engine.dispose);
      await engine.startDiscovery();
      expect(engine.currentSession, isA<CastIdle>());
    });

    test('NoOp.loadMedia throws CastUnsupportedException', () async {
      final engine = NoOpCastEngine.fromReason('test platform');
      addTearDown(engine.dispose);
      const m = CastMedia(url: 'https://x.example/stream.m3u8');
      expect(() => engine.loadMedia(m),
          throwsA(isA<CastUnsupportedException>()));
    });
  });

  group('CastDevice equality', () {
    test('value-equal when fields match', () {
      const a = CastDevice(
        id: 'tv-1',
        name: 'Living Room',
        manufacturer: 'Sony',
        kind: CastDeviceKind.chromecast,
      );
      const b = CastDevice(
        id: 'tv-1',
        name: 'Living Room',
        manufacturer: 'Sony',
        kind: CastDeviceKind.chromecast,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when id differs', () {
      const a = CastDevice(
        id: 'tv-1',
        name: 'Living Room',
        kind: CastDeviceKind.chromecast,
      );
      const b = CastDevice(
        id: 'tv-2',
        name: 'Living Room',
        kind: CastDeviceKind.chromecast,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('CastPlaybackState.copyWith', () {
    test('preserves untouched fields', () {
      const initial = CastPlaybackState(
        position: Duration(seconds: 10),
        total: Duration(seconds: 600),
        playing: true,
        volume: 0.5,
        currentTitle: 'Test',
      );
      final copy = initial.copyWith(playing: false);
      expect(copy.position, initial.position);
      expect(copy.total, initial.total);
      expect(copy.volume, initial.volume);
      expect(copy.currentTitle, initial.currentTitle);
      expect(copy.playing, isFalse);
    });

    test('clearTotal nulls the total field', () {
      const initial = CastPlaybackState(total: Duration(seconds: 60));
      final copy = initial.copyWith(clearTotal: true);
      expect(copy.total, isNull);
    });

    test('clearTitle nulls the title field', () {
      const initial = CastPlaybackState(currentTitle: 'Old');
      final copy = initial.copyWith(clearTitle: true);
      expect(copy.currentTitle, isNull);
    });
  });

  group('CastMedia.resolvedContentType', () {
    test('detects HLS by extension', () {
      const m = CastMedia(url: 'https://x.example/stream.m3u8');
      expect(m.resolvedContentType, 'application/vnd.apple.mpegurl');
    });

    test('detects DASH by extension', () {
      const m = CastMedia(url: 'https://x.example/stream.mpd');
      expect(m.resolvedContentType, 'application/dash+xml');
    });

    test('detects MPEG-TS by extension', () {
      const m = CastMedia(url: 'https://x.example/stream.ts');
      expect(m.resolvedContentType, 'video/mp2t');
    });

    test('explicit override beats inference', () {
      const m = CastMedia(
        url: 'https://x.example/stream.m3u8',
        contentType: 'video/mp4',
      );
      expect(m.resolvedContentType, 'video/mp4');
    });

    test('unknown URL returns octet-stream fallback', () {
      const m = CastMedia(url: 'https://x.example/foo');
      expect(m.resolvedContentType, 'application/octet-stream');
    });
  });

  group('CastMedia.toChannelMap', () {
    test('encodes all primitive fields', () {
      const m = CastMedia(
        url: 'https://x.example/stream.m3u8',
        title: 'Live',
        subtitle: 'Channel 1',
        artworkUrl: 'https://x.example/art.png',
        headers: <String, String>{'User-Agent': 'AWAtv/1.0'},
        streamType: CastStreamType.live,
        startPosition: Duration(seconds: 30),
      );
      final map = m.toChannelMap();
      expect(map['url'], 'https://x.example/stream.m3u8');
      expect(map['title'], 'Live');
      expect(map['subtitle'], 'Channel 1');
      expect(map['artworkUrl'], 'https://x.example/art.png');
      expect(
        map['contentType'],
        'application/vnd.apple.mpegurl',
      );
      expect(map['streamType'], 'LIVE');
      expect(map['startPositionMs'], 30000);
      expect((map['headers'] as Map?)?['User-Agent'], 'AWAtv/1.0');
    });
  });

  group('Sealed states are exhaustive', () {
    // Compile-time guarantee that the switch exhausts every variant.
    // If a new state is added, this test stops compiling.
    test('all variants constructable', () {
      const sessions = <CastSession>[
        CastIdle(),
        CastDiscovering(),
        CastDevicesAvailable(<CastDevice>[]),
        CastConnecting(
          CastDevice(id: 'a', name: 'a', kind: CastDeviceKind.chromecast),
        ),
        CastConnected(
          CastDevice(id: 'a', name: 'a', kind: CastDeviceKind.chromecast),
          CastPlaybackState.idle,
        ),
        CastError('boom'),
      ];
      for (final s in sessions) {
        final label = switch (s) {
          CastIdle() => 'idle',
          CastDiscovering() => 'discovering',
          CastDevicesAvailable() => 'available',
          CastConnecting() => 'connecting',
          CastConnected() => 'connected',
          CastError() => 'error',
        };
        expect(label, isNotEmpty);
      }
    });
  });

  group('Platform diagnostics', () {
    test('TargetPlatform check', () {
      // Sanity — the test harness uses the host platform's default.
      expect(defaultTargetPlatform, isNotNull);
    });
  });
}
