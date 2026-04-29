// ignore_for_file: avoid_slow_async_io — fs probes in test setUp/tearDown are deliberate.
import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// `EpgService.programmesAroundForChannels` is the engine that powers the
/// EPG grid. The service itself is a thin wrapper over Hive — these tests
/// exercise it through a real `AwatvStorage` instance so the contract
/// the UI relies on (sorted output, every requested id present, channels
/// without data → empty list) is verified end-to-end.
void main() {
  late Directory tmp;
  late AwatvStorage storage;
  late EpgService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_epg_svc_');
    storage = AwatvStorage();
    await storage.init(subDir: tmp.path);
    service = EpgService(
      client: EpgClient(),
      storage: storage,
    );
  });

  tearDown(() async {
    await storage.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  EpgProgramme prog(
    String channel,
    String title,
    DateTime start,
    Duration length,
  ) {
    return EpgProgramme(
      channelTvgId: channel,
      start: start,
      stop: start.add(length),
      title: title,
    );
  }

  group('EpgService.programmesAroundForChannels', () {
    test('returns empty map for empty input', () async {
      final out = await service.programmesAroundForChannels(tvgIds: const []);
      expect(out, isEmpty);
    });

    test("sorts each channel's programmes by start ascending", () async {
      final now = DateTime.utc(2026, 4, 28, 18);
      // Insert intentionally out-of-order.
      await storage.putEpg('bbcone.uk', <EpgProgramme>[
        prog('bbcone.uk', 'C', now.add(const Duration(hours: 2)),
            const Duration(hours: 1)),
        prog('bbcone.uk', 'A', now.subtract(const Duration(hours: 1)),
            const Duration(hours: 1)),
        prog('bbcone.uk', 'B', now, const Duration(hours: 1)),
      ]);

      final out = await service.programmesAroundForChannels(
        tvgIds: const ['bbcone.uk'],
        around: now,
      );
      expect(out.keys, ['bbcone.uk']);
      expect(out['bbcone.uk']!.map((p) => p.title).toList(), ['A', 'B', 'C']);
    });

    test('filters programmes outside the +/- window', () async {
      final now = DateTime.utc(2026, 4, 28, 18);
      await storage.putEpg('cnn.us', <EpgProgramme>[
        // Way in the past.
        prog('cnn.us', 'old',
            now.subtract(const Duration(hours: 30)), const Duration(hours: 1)),
        // Inside window.
        prog('cnn.us', 'live', now, const Duration(hours: 1)),
        // Way in the future.
        prog('cnn.us', 'future',
            now.add(const Duration(hours: 30)), const Duration(hours: 1)),
      ]);

      final out = await service.programmesAroundForChannels(
        tvgIds: const ['cnn.us'],
        around: now,
        window: const Duration(hours: 4),
      );
      expect(out['cnn.us']!.map((p) => p.title), ['live']);
    });

    test('keeps programmes that overlap the window edge', () async {
      final now = DateTime.utc(2026, 4, 28, 18);
      // A programme that starts before the window but stops inside it.
      await storage.putEpg('ntv.tr', <EpgProgramme>[
        prog(
          'ntv.tr',
          'edge',
          now.subtract(const Duration(hours: 13)),
          const Duration(hours: 2),
        ),
      ]);
      final out = await service.programmesAroundForChannels(
        tvgIds: const ['ntv.tr'],
        around: now,
      );
      expect(out['ntv.tr']!.map((p) => p.title), ['edge']);
    });

    test('returns empty list for channels with no cached EPG', () async {
      final now = DateTime.utc(2026, 4, 28);
      final out = await service.programmesAroundForChannels(
        tvgIds: const ['unknown.tv'],
        around: now,
      );
      expect(out, contains('unknown.tv'));
      expect(out['unknown.tv'], isEmpty);
    });

    test('every requested id appears in the result map', () async {
      final now = DateTime.utc(2026, 4, 28);
      await storage.putEpg('a.tv', <EpgProgramme>[
        prog('a.tv', 'a', now, const Duration(hours: 1)),
      ]);

      final out = await service.programmesAroundForChannels(
        tvgIds: const ['a.tv', 'b.tv', 'c.tv'],
        around: now,
      );
      expect(out.keys.toSet(), {'a.tv', 'b.tv', 'c.tv'});
      expect(out['a.tv']!.map((p) => p.title), ['a']);
      expect(out['b.tv'], isEmpty);
      expect(out['c.tv'], isEmpty);
    });

    test('skips empty / whitespace tvgIds', () async {
      final now = DateTime.utc(2026, 4, 28);
      final out = await service.programmesAroundForChannels(
        tvgIds: const ['', '   '],
        around: now,
      );
      expect(out, isEmpty);
    });

    test('dedupes repeated tvgIds', () async {
      final now = DateTime.utc(2026, 4, 28);
      await storage.putEpg('dedupe.tv', <EpgProgramme>[
        prog('dedupe.tv', 'one', now, const Duration(hours: 1)),
      ]);
      final out = await service.programmesAroundForChannels(
        tvgIds: const ['dedupe.tv', 'dedupe.tv', 'dedupe.tv'],
        around: now,
      );
      // Map dedupes by key; we still expect the entry to be present once.
      expect(out.length, 1);
      expect(out['dedupe.tv']!.map((p) => p.title), ['one']);
    });

    test('default `around` is now (uses real clock)', () async {
      final wallNow = DateTime.now();
      await storage.putEpg('clock.tv', <EpgProgramme>[
        prog('clock.tv', 'now',
            wallNow.subtract(const Duration(minutes: 5)),
            const Duration(minutes: 30)),
      ]);
      final out = await service.programmesAroundForChannels(
        tvgIds: const ['clock.tv'],
      );
      expect(out['clock.tv']!.map((p) => p.title), ['now']);
    });
  });
}
