// Provider-level tests for the cast engine — focuses on the lifecycle
// transitions exposed via [CastEngine] sealed states. Distinct from
// `cast_engine_test.dart` which covers platform engine factory + media
// type inference; this file focuses on session state machine semantics.

import 'package:awatv_player/awatv_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void mockChannel(String name) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      EventChannel(name),
      MockStreamHandler.inline(
        onListen: (Object? args, MockStreamHandlerEventSink sink) {},
        onCancel: (Object? args) {},
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannel(name.replaceAll('/events', '')),
      (MethodCall call) async => null,
    );
  }

  setUpAll(() {
    mockChannel('awatv/cast/events');
    mockChannel('awatv/airplay/events');
  });

  group('CastDevice', () {
    test('value-equal when fields match (chromecast)', () {
      const a = CastDevice(
        id: 'tv-1',
        name: 'Living Room',
        kind: CastDeviceKind.chromecast,
      );
      const b = CastDevice(
        id: 'tv-1',
        name: 'Living Room',
        kind: CastDeviceKind.chromecast,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value-equal when fields match (airplay)', () {
      const a = CastDevice(
        id: 'apple-tv',
        name: 'Apple TV',
        kind: CastDeviceKind.airplay,
      );
      const b = CastDevice(
        id: 'apple-tv',
        name: 'Apple TV',
        kind: CastDeviceKind.airplay,
      );
      expect(a, equals(b));
    });

    test('not equal when manufacturer differs', () {
      const a = CastDevice(
        id: 'tv',
        name: 'TV',
        manufacturer: 'Sony',
        kind: CastDeviceKind.chromecast,
      );
      const b = CastDevice(
        id: 'tv',
        name: 'TV',
        manufacturer: 'Samsung',
        kind: CastDeviceKind.chromecast,
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when kind differs', () {
      const a = CastDevice(
        id: 'tv',
        name: 'TV',
        kind: CastDeviceKind.chromecast,
      );
      const b = CastDevice(
        id: 'tv',
        name: 'TV',
        kind: CastDeviceKind.airplay,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('CastPlaybackState', () {
    test('idle is the documented zero value', () {
      const idle = CastPlaybackState.idle;
      expect(idle.position, Duration.zero);
      expect(idle.playing, isFalse);
      expect(idle.total, isNull);
      expect(idle.currentTitle, isNull);
    });

    test('copyWith preserves untouched fields', () {
      const initial = CastPlaybackState(
        position: Duration(seconds: 5),
        total: Duration(minutes: 90),
        playing: true,
        volume: 0.75,
        currentTitle: 'Movie',
      );
      final copy = initial.copyWith(position: const Duration(seconds: 10));
      expect(copy.position, const Duration(seconds: 10));
      expect(copy.total, initial.total);
      expect(copy.playing, initial.playing);
      expect(copy.volume, initial.volume);
      expect(copy.currentTitle, initial.currentTitle);
    });

    test('clearTotal flag wins over total parameter', () {
      const initial = CastPlaybackState(total: Duration(seconds: 60));
      // Even if both are passed, clearTotal=true forces null.
      final copy = initial.copyWith(
        total: const Duration(seconds: 90),
        clearTotal: true,
      );
      expect(copy.total, isNull);
    });

    test('clearTitle flag wins over title parameter', () {
      const initial = CastPlaybackState(currentTitle: 'Old');
      final copy = initial.copyWith(
        currentTitle: 'New',
        clearTitle: true,
      );
      expect(copy.currentTitle, isNull);
    });
  });

  group('CastSession state machine', () {
    test('CastIdle is a singleton with itself', () {
      const a = CastIdle();
      const b = CastIdle();
      expect(a, equals(b));
      expect(identical(a.runtimeType, b.runtimeType), isTrue);
    });

    test('CastDiscovering is distinct from CastIdle', () {
      expect(const CastDiscovering(), isNot(equals(const CastIdle())));
    });

    test('CastConnecting carries the target device', () {
      const device = CastDevice(
        id: 'd',
        name: 'D',
        kind: CastDeviceKind.chromecast,
      );
      const connecting = CastConnecting(device);
      expect(connecting.target, device);
    });

    test('CastConnected carries target device + playback state', () {
      const device = CastDevice(
        id: 'd',
        name: 'D',
        kind: CastDeviceKind.chromecast,
      );
      const connected = CastConnected(device, CastPlaybackState.idle);
      expect(connected.target, device);
      expect(connected.state, CastPlaybackState.idle);
    });

    test('CastConnected.withState swaps the playback state only', () {
      const device = CastDevice(
        id: 'd',
        name: 'D',
        kind: CastDeviceKind.chromecast,
      );
      const initial = CastConnected(device, CastPlaybackState.idle);
      final next = initial.withState(
        const CastPlaybackState(playing: true),
      );
      expect(next.target, device);
      expect(next.state.playing, isTrue);
    });

    test('CastError carries the message', () {
      const error = CastError('boom');
      expect(error.message, 'boom');
    });

    test('CastDevicesAvailable carries the list', () {
      const list = <CastDevice>[
        CastDevice(id: 'a', name: 'A', kind: CastDeviceKind.chromecast),
        CastDevice(id: 'b', name: 'B', kind: CastDeviceKind.airplay),
      ];
      const avail = CastDevicesAvailable(list);
      expect(avail.devices, hasLength(2));
    });
  });

  group('CastDeviceKind enum', () {
    test('has chromecast, airplay, and dlna', () {
      expect(
        CastDeviceKind.values,
        containsAll(<CastDeviceKind>[
          CastDeviceKind.chromecast,
          CastDeviceKind.airplay,
          CastDeviceKind.dlna,
        ]),
      );
    });

    test('names are stable for persistence', () {
      expect(CastDeviceKind.chromecast.name, 'chromecast');
      expect(CastDeviceKind.airplay.name, 'airplay');
      expect(CastDeviceKind.dlna.name, 'dlna');
    });

    test('CastDeviceKindLabel renders Chromecast / AirPlay / DLNA', () {
      expect(CastDeviceKind.chromecast.displayName, 'Chromecast');
      expect(CastDeviceKind.airplay.displayName, 'AirPlay');
      expect(CastDeviceKind.dlna.displayName, 'DLNA');
    });
  });

  group('CastUnsupportedException', () {
    test('toString contains the reason', () {
      final ex = CastUnsupportedException('boom');
      expect(ex.toString(), contains('boom'));
    });
  });

  group('NoOpCastEngine lifecycle', () {
    test('connect throws CastUnsupportedException', () async {
      final engine = NoOpCastEngine.fromReason('test platform');
      addTearDown(engine.dispose);
      const device = CastDevice(
        id: 'x',
        name: 'X',
        kind: CastDeviceKind.chromecast,
      );
      await expectLater(
        () => engine.connect(device),
        throwsA(isA<CastUnsupportedException>()),
      );
    });

    test('startDiscovery is a no-op (does not throw)', () async {
      final engine = NoOpCastEngine.fromReason('test platform');
      addTearDown(engine.dispose);
      await engine.startDiscovery();
      // Sessions stream still holds CastIdle.
      expect(engine.currentSession, isA<CastIdle>());
    });

    test('disconnect is idempotent', () async {
      final engine = NoOpCastEngine.fromReason('test platform');
      addTearDown(engine.dispose);
      await engine.disconnect();
      await engine.disconnect();
      expect(engine.currentSession, isA<CastIdle>());
    });

    test('loadMedia throws CastUnsupportedException', () async {
      final engine = NoOpCastEngine.fromReason('test platform');
      addTearDown(engine.dispose);
      const m = CastMedia(url: 'http://x.example/stream.m3u8');
      await expectLater(
        () => engine.loadMedia(m),
        throwsA(isA<CastUnsupportedException>()),
      );
    });
  });

  group('CastEngine.platform factory', () {
    test('returns a non-null engine and survives dispose', () async {
      final engine = CastEngine.platform();
      // Must succeed without crashing; the returned engine may be a
      // NoOp on platforms without a native cast layer.
      expect(engine, isNotNull);
      // First emission is the cached idle state.
      final initial = await engine.sessions().first;
      expect(initial, isA<CastIdle>());
      await engine.dispose();
    });
  });
}
